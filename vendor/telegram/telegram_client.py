#!/usr/bin/env python3
"""DankChat background daemon — Telegram MTProto client with UNIX domain socket IPC server."""
import os
import sys
import json
import time
import asyncio
import subprocess
import signal
import socket
import re
import hashlib
from datetime import datetime

# Default Telegram API credentials (Official Telegram Android/Desktop public client IDs)
# Users can also provide custom api_id / api_hash in ~/.config/dankchat/telegram/config.json
DEFAULT_API_ID = 2040
DEFAULT_API_HASH = "b18441a1ff607e10a989891a5462e627"

CONFIG_DIR = os.environ.get("DANKCHAT_TELEGRAM_CONFIG", os.path.expanduser("~/.config/dankchat/telegram"))
CACHE_DIR = os.environ.get("DANKCHAT_TELEGRAM_CACHE", os.path.expanduser("~/.cache/dankchat/telegram"))
AVATARS_DIR = os.path.join(CACHE_DIR, "avatars")
MEDIA_DIR = os.path.join(CACHE_DIR, "media")
RUN_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
TELEGRAM_RUN_DIR = os.environ.get("DANKCHAT_TELEGRAM_RUNTIME", os.path.join(RUN_DIR, "dankchat", "telegram"))

SOCK_PATH = os.path.join(TELEGRAM_RUN_DIR, "telegram.sock")
PID_PATH = os.path.join(TELEGRAM_RUN_DIR, "daemon.pid")
SESSION_PATH = os.path.join(CONFIG_DIR, "telegram.session")
QR_PATH = os.path.join(CACHE_DIR, "login_qr.png")

for d in (CONFIG_DIR, CACHE_DIR, AVATARS_DIR, MEDIA_DIR, TELEGRAM_RUN_DIR):
    os.makedirs(d, mode=0o700, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except Exception:
        pass

try:
    from telethon import TelegramClient, events, functions, types
    from telethon.tl.types import User, Chat, Channel, MessageMediaPhoto, MessageMediaDocument, MessageMediaWebPage, WebPage, WebPagePending, WebPageEmpty, InputReportReasonSpam, ReactionEmoji, DocumentAttributeVideo, DocumentAttributeAudio, DocumentAttributeFilename
    from telethon.tl.functions.channels import LeaveChannelRequest
    from telethon.tl.functions.messages import DeleteChatUserRequest, ReportSpamRequest, SendReactionRequest
    from telethon.tl.functions.account import ReportPeerRequest
    from telethon.utils import get_display_name
    import qrcode

except ImportError as e:
    print(f"Required library missing: {e}", file=sys.stderr)
    sys.exit(1)

def load_config():
    cfg_file = os.path.join(CONFIG_DIR, "config.json")
    if os.path.exists(cfg_file):
        try:
            with open(cfg_file, "r", encoding="utf-8") as f:
                d = json.load(f)
                return d.get("api_id", DEFAULT_API_ID), d.get("api_hash", DEFAULT_API_HASH)
        except Exception:
            pass
    return DEFAULT_API_ID, DEFAULT_API_HASH

def get_avatar_color(name):
    """Generate consistent aesthetic pastel hue from name."""
    colors = [
        "#e57373", "#f06292", "#ba68c8", "#9575cd",
        "#7986cb", "#64b5f6", "#4fc3f7", "#4dd0e1",
        "#4db6ac", "#81c784", "#aed581", "#ffb74d",
        "#ff8a65", "#a1887f", "#90a4ae"
    ]
    h = sum(ord(c) for c in (name or "T"))
    return colors[h % len(colors)]

def get_initials(name):
    if not name:
        return "TG"
    parts = name.strip().split()
    if len(parts) >= 2:
        return (parts[0][0] + parts[-1][0]).upper()
    return name.strip()[:2].upper()

def message_reactions(m):
    reactions_list = []
    if hasattr(m, "reactions") and m.reactions and hasattr(m.reactions, "results"):
        for r in m.reactions.results:
            emoticon = ""
            if isinstance(r.reaction, ReactionEmoji):
                emoticon = r.reaction.emoticon
            elif hasattr(r.reaction, "document_id"):
                emoticon = "⭐"
            if emoticon:
                if emoticon in ("\u2764", "❤"):
                    emoticon = "❤️"
                is_chosen = (getattr(r, "chosen_order", None) is not None) or bool(getattr(r, "chosen", False))
                reactions_list.append({
                    "emoticon": emoticon,
                    "count": r.count,
                    "chosen": is_chosen,
                    "custom_id": str(getattr(r.reaction, "document_id", "") or "")
                })
    return reactions_list


def format_message_action(msg):
    if not msg or not getattr(msg, "action", None):
        return ""
    act = msg.action
    act_type = type(act).__name__
    if act_type in ("MessageActionChatAddUser", "MessageActionChatJoinedByLink", "MessageActionChatJoinedByRequest"):
        return "joined the group"
    elif act_type == "MessageActionChatDeleteUser":
        return "left the group"
    elif act_type == "MessageActionChatCreate":
        return "Group created"
    elif act_type == "MessageActionChatEditTitle":
        return f"Changed group name to {getattr(act, 'title', '')}" if getattr(act, 'title', '') else "Changed group name"
    elif act_type == "MessageActionChatEditPhoto":
        return "Changed group photo"
    elif act_type == "MessageActionPinMessage":
        return "Pinned a message"
    elif act_type in ("MessageActionGroupCall", "MessageActionGroupCallScheduled"):
        return "Video chat"
    elif act_type == "MessageActionTopicCreate":
        return f"Topic created: {getattr(act, 'title', '')}" if getattr(act, 'title', '') else "Topic created"
    elif act_type == "MessageActionTopicEdit":
        return "Topic edited"
    else:
        return act_type.replace("MessageAction", "").strip()

from telethon.sessions.sqlite import SQLiteSession
import sqlite3

class SafeSQLiteSession(SQLiteSession):
    def _cursor(self):
        if self._conn is None:
            self._conn = sqlite3.connect(self.filename, timeout=30.0, check_same_thread=False)
            try:
                self._conn.execute("PRAGMA busy_timeout = 30000")
            except Exception:
                pass
        return self._conn.cursor()

class TelegramBackend:
    def __init__(self):
        api_id, api_hash = load_config()
        self.api_id = api_id
        self.api_hash = api_hash
        self.client = TelegramClient(SafeSQLiteSession(SESSION_PATH), self.api_id, self.api_hash)
        self.qr_login_obj = None
        self.phone_code_hash = None
        self.phone_number = None
        self.running = True
        self.dialogs_cache = []
        self.unread_total = 0
        self.cached_avatars = {}
        self.pinned_cache = {}  # chat_id -> list of pinned msgs
        self.messages_cache = {}  # "chat_id_topic_id" -> (msgs, timestamp)

    async def start(self):
        # Save PID file with strict permissions
        pid_payload = json.dumps({
            "pid": os.getpid(),
            "starttime": self.get_my_starttime(),
            "started_at": time.time()
        })
        fd = os.open(PID_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with open(fd, "w", encoding="utf-8") as f:
            f.write(pid_payload)

        # Connect to Telegram
        await self.client.connect()

        # Register live event listeners
        @self.client.on(events.NewMessage)
        async def message_handler(event):
            try:
                cid = event.chat_id
                for ck in list(self.messages_cache.keys()):
                    if ck.startswith(f"{cid}_") or ck == str(cid):
                        self.messages_cache.pop(ck, None)
                if hasattr(self, "chat_messages_cache"):
                    self.chat_messages_cache.pop(cid, None)
                    if str(cid).lstrip("-").isdigit():
                        self.chat_messages_cache.pop(int(cid), None)
            except Exception:
                pass
            await self.update_unread_count()
            asyncio.create_task(self.refresh_dialogs_cache())
            self.notify_shell_refresh()
            if not event.out:
                asyncio.create_task(self.notify_incoming_message(event))

        @self.client.on(events.MessageEdited)
        async def edit_handler(event):
            try:
                cid = event.chat_id
                for ck in list(self.messages_cache.keys()):
                    if ck.startswith(f"{cid}_") or ck == str(cid):
                        self.messages_cache.pop(ck, None)
                if hasattr(self, "chat_messages_cache"):
                    self.chat_messages_cache.pop(cid, None)
                    if str(cid).lstrip("-").isdigit():
                        self.chat_messages_cache.pop(int(cid), None)
            except Exception:
                pass
            self.notify_shell_refresh()

        @self.client.on(events.MessageDeleted)
        async def delete_handler(event):
            try:
                cid = getattr(event, "chat_id", None)
                if cid:
                    for ck in list(self.messages_cache.keys()):
                        if ck.startswith(f"{cid}_") or ck == str(cid):
                            self.messages_cache.pop(ck, None)
                    if hasattr(self, "chat_messages_cache"):
                        self.chat_messages_cache.pop(cid, None)
                        if str(cid).lstrip("-").isdigit():
                            self.chat_messages_cache.pop(int(cid), None)
                else:
                    self.messages_cache.clear()
                    if hasattr(self, "chat_messages_cache"):
                        self.chat_messages_cache.clear()
            except Exception:
                pass
            self.notify_shell_refresh()

        @self.client.on(events.MessageRead)
        async def read_handler(event):
            await self.update_unread_count()
            asyncio.create_task(self.refresh_dialogs_cache())
            self.notify_shell_refresh()

        # Start Unix Socket Server
        if os.path.exists(SOCK_PATH):
            try:
                os.unlink(SOCK_PATH)
            except Exception:
                pass

        server = await asyncio.start_unix_server(self.handle_client, path=SOCK_PATH)
        try:
            os.chmod(SOCK_PATH, 0o600)
        except Exception:
            pass

        print(f"DankChat daemon listening on {SOCK_PATH}")
        asyncio.create_task(self.refresh_dialogs_cache())

        async with server:
            while self.running:
                await asyncio.sleep(1)

    def get_my_starttime(self):
        try:
            with open(f"/proc/{os.getpid()}/stat", "r") as f:
                fields = f.read().split(")")[1].split()
                return int(fields[19])
        except Exception:
            return 0

    def notify_shell_refresh(self):
        try:
            subprocess.Popen(["dms", "ipc", "call", "dankChat", "refresh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    async def notify_incoming_message(self, event):
        try:
            m = event.message
            if not m or m.out:
                return
            cid = event.chat_id
            sender = await event.get_sender()
            sender_name = get_display_name(sender) or "Telegram"
            preview = m.message or ("Media" if m.media else "New message")
            if len(preview) > 120:
                preview = preview[:117] + "..."
            cmd = [
                "notify-send",
                "-u", "normal",
                "-i", "dialog-information",
                "--app-name", "DankChat",
                sender_name,
                preview
            ]
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    async def update_unread_count(self):
        if not await self.client.is_user_authorized():
            self.unread_total = 0
            return 0
        try:
            dialogs = await self.client.get_dialogs(limit=50)
            total = sum(d.unread_count or 0 for d in dialogs)
            self.unread_total = total
            return total
        except Exception as e:
            return self.unread_total

    async def get_chat_avatar(self, entity):
        """Fetch and cache entity profile photo as local file path."""
        try:
            ent_id = entity.id
            if ent_id in self.cached_avatars and os.path.exists(self.cached_avatars[ent_id]):
                return self.cached_avatars[ent_id]

            avatar_file = os.path.join(AVATARS_DIR, f"{ent_id}.jpg")
            if os.path.exists(avatar_file) and os.path.getsize(avatar_file) > 0:
                self.cached_avatars[ent_id] = avatar_file
                return avatar_file

            path = await self.client.download_profile_photo(entity, file=avatar_file, download_big=False)
            if path and os.path.exists(path):
                try:
                    os.chmod(path, 0o600)
                except Exception:
                    pass
                self.cached_avatars[ent_id] = path
                return path
        except Exception:
            pass
        return ""

    async def refresh_dialogs_cache(self, limit=40):
        if not await self.client.is_user_authorized():
            self.dialogs_cache = []
            return []
        try:
            dialogs = await self.client.get_dialogs(limit=limit)
            result = []
            total_unread = 0

            for d in dialogs:
                ent = d.entity
                title = d.name or "Unknown"
                username = getattr(ent, "username", "") or ""
                is_user = isinstance(ent, User)
                is_group = isinstance(ent, (Chat, Channel)) and getattr(ent, "megagroup", False) or isinstance(ent, Chat)
                is_channel = isinstance(ent, Channel) and not getattr(ent, "megagroup", False)
                is_forum = isinstance(ent, Channel) and bool(getattr(ent, "forum", False))

                unread = d.unread_count or 0
                total_unread += unread

                last_msg_text = ""
                last_msg_date = ""
                last_msg_time = ""
                last_msg_out = False
                media_type = ""

                if d.message:
                    last_msg_out = bool(d.message.out)
                    last_msg_text = d.message.message or ""
                    if not last_msg_text and getattr(d.message, "action", None):
                        last_msg_text = format_message_action(d.message)
                    if d.message.media:
                        if isinstance(d.message.media, MessageMediaPhoto):
                            media_type = "photo"
                            if not last_msg_text:
                                last_msg_text = "📷 Photo"
                        elif isinstance(d.message.media, MessageMediaDocument):
                            doc = getattr(d.message.media, "document", None)
                            mime = getattr(doc, "mime_type", "") if doc else ""
                            if "audio" in mime or "ogg" in mime:
                                media_type = "voice"
                                if not last_msg_text:
                                    last_msg_text = "🎤 Voice message"
                            elif "video" in mime:
                                media_type = "video"
                                if not last_msg_text:
                                    last_msg_text = "🎬 Video"
                            elif "webp" in mime:
                                media_type = "sticker"
                                if not last_msg_text:
                                    last_msg_text = "🌟 Sticker"
                            else:
                                media_type = "document"
                                if not last_msg_text:
                                    last_msg_text = "📄 Document"

                    dt = d.message.date
                    if dt:
                        last_msg_date = dt.strftime("%Y-%m-%d")
                        now = datetime.now(dt.tzinfo)
                        if dt.date() == now.date():
                            last_msg_time = dt.strftime("%H:%M")
                        else:
                            last_msg_time = dt.strftime("%b %d")

                avatar_path = await self.get_chat_avatar(ent)

                online = False
                if is_user and getattr(ent, "status", None):
                    status_name = type(ent.status).__name__
                    if status_name == "UserStatusOnline":
                        online = True

                read_outbox_max_id = getattr(d.dialog, 'read_outbox_max_id', 0) if hasattr(d, 'dialog') else 0
                last_msg_is_read = False
                last_msg_status = ""
                if d.message and d.message.out:
                    last_msg_is_read = bool(read_outbox_max_id > 0 and d.message.id <= read_outbox_max_id)
                    last_msg_status = "read" if last_msg_is_read else "sent"

                result.append({
                    "id": d.id,
                    "title": title,
                    "username": username,
                    "is_user": is_user,
                    "is_group": is_group,
                    "is_channel": is_channel,
                    "is_forum": is_forum,
                    "unread_count": unread,
                    "pinned": bool(getattr(d.dialog, "pinned", False)),
                    "read_outbox_max_id": read_outbox_max_id,
                    "avatar": avatar_path,
                    "initials": get_initials(title),
                    "color": get_avatar_color(title),
                    "online": online,
                    "last_message": {
                        "text": last_msg_text,
                        "timestamp": int(d.message.date.timestamp()) if d.message and d.message.date else 0,
                        "time": last_msg_time,
                        "date": last_msg_date,
                        "out": last_msg_out,
                        "is_read": last_msg_is_read,
                        "status": last_msg_status,
                        "media_type": media_type
                    }
                })

            self.dialogs_cache = result
            self.unread_total = total_unread
            return result
        except Exception as e:
            print(f"Error refreshing dialogs: {e}", file=sys.stderr)
            return self.dialogs_cache

    async def download_media_bg(self, media, target_path, thumb=None):
        try:
            if not os.path.exists(target_path):
                kwargs = {"file": target_path}
                if thumb is not None:
                    kwargs["thumb"] = thumb
                path = await self.client.download_media(media, **kwargs)
                if path and os.path.exists(path):
                    try:
                        os.chmod(path, 0o600)
                    except Exception:
                        pass
                    return path
            return target_path
        except Exception:
            pass
        return ""

    async def get_pinned_messages(self, chat_id, topic_id=None):
        """Fetch pinned messages for a chat. Uses cache to avoid repeated fetches."""
        if not await self.client.is_user_authorized():
            return []
        cid = int(chat_id)
        # Return from cache if available
        if cid in self.pinned_cache:
            return self.pinned_cache[cid]
        try:
            from telethon.tl.types import InputMessagesFilterPinned
            entity = await self.client.get_entity(cid)
            messages = await self.client.get_messages(entity, limit=50, filter=InputMessagesFilterPinned)
            chat_title = getattr(entity, "first_name", "") or getattr(entity, "title", "User")
            chat_avatar = self.cached_avatars.get(cid, "")
            is_group_or_channel = isinstance(entity, (Chat, Channel))
            if not hasattr(self, 'cached_senders'):
                self.cached_senders = {}
            result = []
            for m in messages:
                sender_name = "You" if m.out else chat_title
                sender_avatar = chat_avatar if not m.out else ""
                sender_color = get_avatar_color(sender_name)
                if not m.out and is_group_or_channel and m.sender_id:
                    if m.sender_id in self.cached_senders:
                        cached = self.cached_senders[m.sender_id]
                        sender_name = cached["name"]
                        sender_avatar = cached["avatar"]
                        sender_color = cached["color"]
                    else:
                        try:
                            sender = await self.client.get_entity(m.sender_id)
                            sender_name = getattr(sender, "first_name", "") or getattr(sender, "title", "") or getattr(sender, "username", "") or "User"
                            sender_avatar = ""
                            sender_color = get_avatar_color(sender_name)
                            self.cached_senders[m.sender_id] = {"name": sender_name, "avatar": sender_avatar, "color": sender_color}
                        except Exception:
                            pass
                text = m.message or ""
                if not text and m.media:
                    text = "📎 Media"
                # Handle webpage metadata for pinned messages
                webpage_meta = None
                media_type = ""
                media_path = ""
                if m.media and isinstance(m.media, MessageMediaWebPage):
                    wp = m.media.webpage
                    if isinstance(wp, (WebPage, WebPagePending, WebPageEmpty)):
                        media_type = "webpage"
                        wp_photo = ""
                        if hasattr(wp, "photo") and wp.photo:
                            wp_photo_f = os.path.join(MEDIA_DIR, f"webpage_{m.id}_{cid}.jpg")
                            if os.path.exists(wp_photo_f):
                                wp_photo = wp_photo_f
                            else:
                                asyncio.create_task(self.download_media_bg(wp.photo, wp_photo_f))
                        webpage_meta = {
                            "site_name": getattr(wp, "site_name", "") or "",
                            "title": getattr(wp, "title", "") or "",
                            "description": getattr(wp, "description", "") or "",
                            "url": getattr(wp, "url", "") or getattr(wp, "display_url", "") or "",
                            "photo": wp_photo
                        }
                dt = m.date
                time_str = dt.strftime("%H:%M") if dt else ""
                date_str = dt.strftime("%b %d, %Y") if dt else ""
                result.append({
                    "id": m.id,
                    "text": text,
                    "sender": sender_name,
                    "sender_id": m.sender_id,
                    "sender_avatar": sender_avatar,
                    "sender_color": sender_color,
                    "out": m.out,
                    "date": date_str,
                    "timestamp": int(m.date.timestamp()) if m.date else 0,
                    "time": time_str,
                    "pinned": True,
                    "reactions": message_reactions(m),
                    "sender_name": sender_name,
                    "reply_to": (getattr(m.reply_to, "reply_to_top_id", None) or getattr(m.reply_to, "reply_to_msg_id", None)) if m.reply_to else None,
                    "media": bool(m.media),
                    "media_type": media_type,
                    "media_path": media_path,
                    "webpage": webpage_meta,
                })
            self.pinned_cache[cid] = result
            return result
        except Exception:
            return []

    async def get_messages_for_chat(self, chat_id, limit=50, topic_id=None, around_id=None):
        if not await self.client.is_user_authorized():
            return []
        try:
            cid = int(chat_id)
            entity = await self.client.get_entity(cid)
            kwargs = {"limit": limit}
            if around_id is not None:
                kwargs.update(offset_id=int(around_id) + 1, add_offset=-(limit // 2))
            if topic_id:
                kwargs["reply_to"] = int(topic_id)
            messages = await self.client.get_messages(entity, **kwargs)

            read_outbox_max_id = 0
            chat_title = get_display_name(entity) or getattr(entity, "title", "User")
            chat_avatar = self.cached_avatars.get(cid, "")
            is_group_or_channel = isinstance(entity, (Chat, Channel))

            for d in self.dialogs_cache:
                if d.get("id") == cid:
                    read_outbox_max_id = d.get("read_outbox_max_id", 0)
                    if d.get("avatar"):
                        chat_avatar = d["avatar"]
                    break

            if not hasattr(self, 'cached_senders'):
                self.cached_senders = {}

            result = []
            msg_map = {m.id: m for m in messages}
            for m in messages:
                sender_name = "You" if m.out else chat_title
                sender_avatar = chat_avatar if not m.out else ""
                sender_color = get_avatar_color(sender_name)

                if not m.out and is_group_or_channel and m.sender_id:
                    if m.sender_id in self.cached_senders:
                        cached = self.cached_senders[m.sender_id]
                        sender_name = cached["name"]
                        sender_avatar = cached["avatar"]
                        sender_color = cached["color"]
                    else:
                        try:
                            sender = await self.client.get_entity(m.sender_id)
                            sender_name = get_display_name(sender) or getattr(sender, "username", "") or "User"
                            sender_color = get_avatar_color(sender_name)
                            self.cached_senders[m.sender_id] = {"name": sender_name, "avatar": "", "color": sender_color}
                        except Exception:
                            sender_name = "User"

                media_type = ""
                media_path = ""
                media_thumb = ""
                media_info = None
                webpage_meta = None
                if m.media:
                    if isinstance(m.media, MessageMediaPhoto):
                        media_type = "photo"
                        photo_f = os.path.join(MEDIA_DIR, f"photo_{m.id}_{cid}.jpg")
                        if os.path.exists(photo_f):
                            media_path = photo_f
                            media_thumb = photo_f
                        else:
                            asyncio.create_task(self.download_media_bg(m.media, photo_f))
                    elif isinstance(m.media, MessageMediaDocument):
                        doc = getattr(m.media, "document", None)
                        mime = getattr(doc, "mime_type", "") if doc else ""
                        attrs = getattr(doc, "attributes", []) if doc else []
                        is_vid = "video" in mime or any(isinstance(a, DocumentAttributeVideo) for a in attrs)
                        if "audio" in mime or "ogg" in mime or any(isinstance(a, DocumentAttributeAudio) for a in attrs):
                            media_type = "voice"
                        elif is_vid:
                            media_type = "video"
                            duration = 0
                            w = 0
                            h = 0
                            file_name = "video.mp4"
                            for a in attrs:
                                if isinstance(a, DocumentAttributeVideo):
                                    duration = getattr(a, "duration", 0) or 0
                                    w = getattr(a, "w", 0) or 0
                                    h = getattr(a, "h", 0) or 0
                                elif hasattr(a, "file_name") and a.file_name:
                                    file_name = a.file_name

                            mins = int(duration) // 60
                            secs = int(duration) % 60
                            fmt_dur = f"{mins:02d}:{secs:02d}"

                            size_bytes = getattr(doc, "size", 0) or 0
                            if size_bytes >= 1024 * 1024:
                                fmt_size = f"{size_bytes / (1024 * 1024):.1f} MB"
                            elif size_bytes >= 1024:
                                fmt_size = f"{size_bytes / 1024:.0f} KB"
                            else:
                                fmt_size = f"{size_bytes} B"

                            video_thumb_f = os.path.join(MEDIA_DIR, f"thumb_video_{m.id}_{cid}.jpg")
                            if os.path.exists(video_thumb_f):
                                media_thumb = video_thumb_f
                            else:
                                asyncio.create_task(self.download_media_bg(m.media, video_thumb_f, thumb=-1))

                            video_f = os.path.join(MEDIA_DIR, f"video_{m.id}_{cid}.mp4")
                            if os.path.exists(video_f) and os.path.getsize(video_f) > 0:
                                media_path = video_f

                            media_info = {
                                "duration": duration,
                                "formatted_duration": fmt_dur,
                                "width": w,
                                "height": h,
                                "size": fmt_size,
                                "file_name": file_name,
                                "is_downloaded": bool(media_path)
                            }
                        elif "webp" in mime:
                            media_type = "sticker"
                            sticker_f = os.path.join(MEDIA_DIR, f"sticker_{m.id}_{cid}.webp")
                            if os.path.exists(sticker_f):
                                media_path = sticker_f
                                media_thumb = sticker_f
                            else:
                                asyncio.create_task(self.download_media_bg(m.media, sticker_f))
                        else:
                            media_type = "document"
                            file_name = "file"
                            for a in attrs:
                                if hasattr(a, "file_name") and a.file_name:
                                    file_name = a.file_name
                            size_bytes = getattr(doc, "size", 0) or 0
                            fmt_size = f"{size_bytes / (1024 * 1024):.1f} MB" if size_bytes >= 1024 * 1024 else f"{size_bytes / 1024:.0f} KB"
                            media_info = {
                                "file_name": file_name,
                                "size": fmt_size
                            }
                    elif isinstance(m.media, MessageMediaWebPage):
                        wp = m.media.webpage
                        if isinstance(wp, (WebPage, WebPagePending, WebPageEmpty)):
                            media_type = "webpage"
                            wp_photo = ""
                            if hasattr(wp, "photo") and wp.photo:
                                wp_photo_f = os.path.join(MEDIA_DIR, f"webpage_{m.id}_{cid}.jpg")
                                if os.path.exists(wp_photo_f):
                                    wp_photo = wp_photo_f
                                else:
                                    asyncio.create_task(self.download_media_bg(wp.photo, wp_photo_f))
                            webpage_meta = {
                                "site_name": getattr(wp, "site_name", "") or "",
                                "title": getattr(wp, "title", "") or "",
                                "description": getattr(wp, "description", "") or "",
                                "url": getattr(wp, "url", "") or getattr(wp, "display_url", "") or "",
                                "photo": wp_photo
                            }

                dt = m.date
                time_str = dt.strftime("%H:%M") if dt else ""
                date_str = dt.strftime("%b %d, %Y") if dt else ""

                is_read = bool(m.out and read_outbox_max_id > 0 and m.id <= read_outbox_max_id)
                msg_status = "read" if is_read else ("sent" if m.out else "")

                reactions_list = message_reactions(m)

                reply_to_id = None
                if m.reply_to:
                    is_forum = getattr(m.reply_to, "forum_topic", False)
                    r_msg_id = getattr(m.reply_to, "reply_to_msg_id", None)
                    top_id = getattr(m.reply_to, "reply_to_top_id", None)
                    if is_forum:
                        if top_id and r_msg_id and r_msg_id != top_id:
                            reply_to_id = r_msg_id
                    else:
                        reply_to_id = r_msg_id

                reply_to_sender = ""
                reply_to_text = getattr(m.reply_to, "quote_text", "") or "" if m.reply_to else ""
                if reply_to_id and reply_to_id in msg_map:
                    target_m = msg_map[reply_to_id]
                    if not reply_to_text:
                        reply_to_text = target_m.message or (format_message_action(target_m) if getattr(target_m, "action", None) else ("Media" if target_m.media else ""))
                    reply_to_sender = "You" if target_m.out else (self.cached_senders.get(target_m.sender_id, {}).get("name") or chat_title)

                result.append({
                    "id": m.id,
                    "chat_id": cid,
                    "sender_id": m.sender_id,
                    "sender_name": sender_name,
                    "sender_avatar": sender_avatar,
                    "sender_initials": get_initials(sender_name),
                    "sender_color": sender_color,
                    "text": m.message or (format_message_action(m) if getattr(m, "action", None) else ""),
                    "time": time_str,
                    "date": date_str,
                    "timestamp": int(m.date.timestamp()) if m.date else 0,
                    "out": bool(m.out),
                    "status": msg_status,
                    "is_read": is_read,
                    "pinned": bool(getattr(m, "pinned", False)),
                    "is_edited": bool(getattr(m, "edit_date", None) is not None),
                    "reactions": reactions_list,
                    "is_service": bool(getattr(m, "action", None)),
                    "media_type": media_type,
                    "media_path": media_path,
                    "media_thumb": media_thumb,
                    "media_info": media_info,
                    "webpage": webpage_meta,
                    "reply_to_msg_id": reply_to_id,
                    "reply_to_sender": reply_to_sender,
                    "reply_to_text": reply_to_text
                })

            if not hasattr(self, 'chat_messages_cache'):
                self.chat_messages_cache = {}
            self.chat_messages_cache[cid] = result
            return result
        except Exception as e:
            print(f"Error fetching messages for {chat_id}: {e}", file=sys.stderr)
            return getattr(self, 'chat_messages_cache', {}).get(int(chat_id) if str(chat_id).isdigit() else 0, [])

    async def send_message_to_chat(self, chat_id, text, topic_id=None, reply_to=None):
        if not await self.client.is_user_authorized():
            return {"success": False, "error": "Not authorized"}
        try:
            cid = int(chat_id)
            entity = await self.client.get_entity(cid)
            kwargs = {}
            rep_id = int(reply_to) if (reply_to and str(reply_to).lstrip("-").isdigit()) else (int(topic_id) if (topic_id and str(topic_id).lstrip("-").isdigit()) else None)
            if rep_id is not None:
                kwargs["reply_to"] = rep_id
            sent = await self.client.send_message(entity, text, **kwargs)
            # Invalidate message cache so next fetch includes the new message
            cache_key = f"{chat_id}_{topic_id or '0'}"
            self.messages_cache.pop(cache_key, None)
            if cid in getattr(self, "chat_messages_cache", {}):
                del self.chat_messages_cache[cid]
            asyncio.create_task(self.refresh_dialogs_cache())
            return {"success": True, "message_id": sent.id}
        except Exception as e:
            return {"success": False, "error": str(e)}

    async def send_file_to_chat(self, chat_id, file_path, caption="", reply_to=None, topic_id=None):
        if not await self.client.is_user_authorized():
            return {"success": False, "error": "Not authorized"}
        try:
            cid = int(chat_id)
            entity = await self.client.get_entity(cid)
            if not os.path.exists(file_path):
                return {"success": False, "error": f"File not found: {file_path}"}
            rep_id = int(reply_to) if (reply_to and str(reply_to).lstrip("-").isdigit()) else (int(topic_id) if (topic_id and str(topic_id).lstrip("-").isdigit()) else None)
            kwargs = {}
            if rep_id is not None:
                kwargs["reply_to"] = rep_id
            sent = await self.client.send_file(entity, file_path, caption=caption or None, **kwargs)
            # Invalidate message cache so next fetch includes the new file
            for ck in list(self.messages_cache.keys()):
                if ck.startswith(f"{chat_id}_"):
                    self.messages_cache.pop(ck, None)
            if cid in getattr(self, "chat_messages_cache", {}):
                del self.chat_messages_cache[cid]
            asyncio.create_task(self.refresh_dialogs_cache())
            return {"success": True, "message_id": sent.id}
        except Exception as e:
            return {"success": False, "error": str(e)}

    async def mark_chat_read(self, chat_id, topic_id=None):
        if not await self.client.is_user_authorized():
            return {"success": False, "error": "Not authorized"}
        try:
            cid = int(chat_id)
            entity = await self.client.get_entity(cid)
            if topic_id:
                from telethon.tl.functions.messages import ReadDiscussionRequest
                # Get the latest message id in this topic for read_max_id
                msgs = await self.client.get_messages(entity, limit=1, reply_to=int(topic_id))
                read_max_id = msgs[0].id if msgs else 0
                await self.client(ReadDiscussionRequest(peer=entity, msg_id=int(topic_id), read_max_id=read_max_id))
            else:
                await self.client.send_read_acknowledge(entity)
            for d in self.dialogs_cache:
                if d.get("id") == cid:
                    d["unread_count"] = 0
            await self.update_unread_count()
            return {"success": True}
        except Exception as e:
            return {"success": False, "error": str(e)}

    async def execute_command(self, cmd_dict):
        action = cmd_dict.get("action", "")

        if action == "status":
            is_auth = await self.client.is_user_authorized()
            user_info = None
            if is_auth:
                me = await self.client.get_me()
                if me:
                    me_avatar = await self.get_chat_avatar(me)
                    my_name = f"{me.first_name or ''} {me.last_name or ''}".strip() or me.username or "Me"
                    user_info = {
                        "id": me.id,
                        "name": my_name,
                        "username": me.username or "",
                        "phone": me.phone or "",
                        "avatar": me_avatar,
                        "initials": get_initials(my_name)
                    }
            return {
                "running": True,
                "authorized": is_auth,
                "user": user_info,
                "unread_total": self.unread_total,
                "chats_count": len(self.dialogs_cache)
            }

        elif action == "delete_chat":
            chat_id = cmd_dict.get("chat_id")
            if not chat_id:
                return {"success": False, "error": "chat_id required"}
            try:
                cid = int(chat_id)
                entity = await self.client.get_entity(cid)
                await self.client.delete_dialog(entity, revoke=True)
                self.dialogs_cache = [d for d in self.dialogs_cache if d.get("id") != cid]
                await self.update_unread_count()
                return {"success": True, "chat_id": cid}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "leave_chat":
            chat_id = cmd_dict.get("chat_id")
            if not chat_id:
                return {"success": False, "error": "chat_id required"}
            try:
                cid = int(chat_id)
                entity = await self.client.get_entity(cid)
                try:
                    if isinstance(entity, Channel):
                        await self.client(LeaveChannelRequest(channel=entity))
                    elif isinstance(entity, Chat):
                        await self.client(DeleteChatUserRequest(chat_id=cid, user_id='me'))
                    else:
                        await self.client.delete_dialog(entity, revoke=True)
                except Exception:
                    await self.client.delete_dialog(entity)
                self.dialogs_cache = [d for d in self.dialogs_cache if d.get("id") != cid]
                await self.update_unread_count()
                return {"success": True, "chat_id": cid}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "report_spam_and_leave":
            chat_id = cmd_dict.get("chat_id")
            if not chat_id:
                return {"success": False, "error": "chat_id required"}
            try:
                cid = int(chat_id)
                entity = await self.client.get_entity(cid)
                try:
                    await self.client(ReportSpamRequest(peer=entity))
                except Exception:
                    try:
                        await self.client(ReportPeerRequest(peer=entity, reason=InputReportReasonSpam(), message="Spam and scam"))
                    except Exception:
                        pass
                try:
                    if isinstance(entity, Channel):
                        await self.client(LeaveChannelRequest(channel=entity))
                    elif isinstance(entity, Chat):
                        await self.client(DeleteChatUserRequest(chat_id=cid, user_id='me'))
                    else:
                        await self.client.delete_dialog(entity, revoke=True)
                except Exception:
                    await self.client.delete_dialog(entity)
                self.dialogs_cache = [d for d in self.dialogs_cache if d.get("id") != cid]
                await self.update_unread_count()
                return {"success": True, "chat_id": cid}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "delete_message":
            chat_id = cmd_dict.get("chat_id")
            msg_id = cmd_dict.get("message_id")
            if not chat_id or not msg_id:
                return {"success": False, "error": "chat_id and message_id required"}
            try:
                cid = int(chat_id)
                mid = int(msg_id)
                entity = await self.client.get_entity(cid)
                try:
                    await self.client.delete_messages(entity, [mid], revoke=True)
                except Exception:
                    await self.client.delete_messages(entity, [mid])
                for ck in list(self.messages_cache.keys()):
                    if ck.startswith(f"{chat_id}_"):
                        self.messages_cache.pop(ck, None)
                if cid in getattr(self, "chat_messages_cache", {}):
                    del self.chat_messages_cache[cid]
                return {"success": True, "chat_id": cid, "message_id": mid}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "delete_messages":
            chat_id = cmd_dict.get("chat_id")
            msg_ids = cmd_dict.get("message_ids", [])
            if not chat_id or not msg_ids:
                return {"success": False, "error": "chat_id and message_ids required"}
            try:
                cid = int(chat_id)
                entity = await self.client.get_entity(cid)
                mids = [int(m) for m in msg_ids if str(m).isdigit()]
                try:
                    await self.client.delete_messages(entity, mids, revoke=True)
                except Exception:
                    await self.client.delete_messages(entity, mids)
                for ck in list(self.messages_cache.keys()):
                    if ck.startswith(f"{chat_id}_"):
                        self.messages_cache.pop(ck, None)
                if cid in getattr(self, "chat_messages_cache", {}):
                    del self.chat_messages_cache[cid]
                return {"success": True, "chat_id": cid, "deleted_count": len(mids)}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "edit_message":
            chat_id = cmd_dict.get("chat_id")
            msg_id = cmd_dict.get("message_id")
            text = cmd_dict.get("text", "")
            if not chat_id or not msg_id:
                return {"success": False, "error": "chat_id and message_id required"}
            try:
                cid = int(chat_id)
                mid = int(msg_id)
                entity = await self.client.get_entity(cid)
                await self.client.edit_message(entity, mid, text)
                for ck in list(self.messages_cache.keys()):
                    if ck.startswith(f"{chat_id}_"):
                        self.messages_cache.pop(ck, None)
                if cid in getattr(self, "chat_messages_cache", {}):
                    del self.chat_messages_cache[cid]
                return {"success": True, "chat_id": cid, "message_id": mid, "text": text}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "pin_message":
            chat_id = cmd_dict.get("chat_id")
            msg_id = cmd_dict.get("message_id")
            if not chat_id or not msg_id:
                return {"success": False, "error": "chat_id and message_id required"}
            try:
                cid = int(chat_id)
                mid = int(msg_id)
                entity = await self.client.get_entity(cid)
                await self.client.pin_message(entity, mid, notify=True)
                self.pinned_cache.pop(cid, None)
                return {"success": True, "chat_id": cid, "message_id": mid}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "unpin_message":
            chat_id = cmd_dict.get("chat_id")
            msg_id = cmd_dict.get("message_id")
            if not chat_id:
                return {"success": False, "error": "chat_id required"}
            try:
                cid = int(chat_id)
                entity = await self.client.get_entity(cid)
                mid = int(msg_id) if msg_id else None
                await self.client.unpin_message(entity, mid)
                self.pinned_cache.pop(cid, None)
                return {"success": True, "chat_id": cid}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "forward_messages":
            from_chat_id = cmd_dict.get("from_chat_id")
            to_chat_id = cmd_dict.get("to_chat_id")
            msg_ids = cmd_dict.get("message_ids", [])
            if not from_chat_id or not to_chat_id or not msg_ids:
                return {"success": False, "error": "from_chat_id, to_chat_id, and message_ids required"}
            try:
                fcid = int(from_chat_id)
                tcid = int(to_chat_id)
                f_entity = await self.client.get_entity(fcid)
                t_entity = await self.client.get_entity(tcid)
                mids = [int(m) for m in msg_ids if str(m).isdigit()]
                await self.client.forward_messages(t_entity, mids, f_entity)
                if tcid in getattr(self, "chat_messages_cache", {}):
                    del self.chat_messages_cache[tcid]
                return {"success": True, "to_chat_id": tcid, "forwarded_count": len(mids)}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "send_reaction":
            chat_id = cmd_dict.get("chat_id")
            msg_id = cmd_dict.get("message_id")
            emoticon = cmd_dict.get("emoticon")
            if not chat_id or not msg_id:
                return {"success": False, "error": "chat_id and message_id required"}
            if emoticon in ("clear", "remove", "none", "rm", "delete", "empty", "", None):
                emoticon = ""
            try:
                cid = int(chat_id)
                mid = int(msg_id)
                entity = await self.client.get_entity(cid)
                reaction_list = [ReactionEmoji(emoticon=emoticon)] if emoticon else []
                await self.client(SendReactionRequest(peer=entity, msg_id=mid, reaction=reaction_list))
                for ck in list(self.messages_cache):
                    if ck.startswith(f"{chat_id}_"):
                        self.messages_cache.pop(ck, None)
                self.pinned_cache.pop(cid, None)
                if cid in getattr(self, "chat_messages_cache", {}):
                    del self.chat_messages_cache[cid]
                return {"success": True, "chat_id": cid, "message_id": mid, "emoticon": emoticon}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "forum_topics":
            chat_id = cmd_dict.get("chat_id")
            if not chat_id:
                return {"success": False, "error": "chat_id required"}
            if not await self.client.is_user_authorized():
                return {"success": False, "error": "Not authorized"}
            try:
                cid = int(chat_id)
                entity = await self.client.get_entity(cid)
                chat_title = getattr(entity, "title", "Chat")
                result = await self.client(functions.messages.GetForumTopicsRequest(
                    peer=entity,
                    offset_date=None,
                    offset_id=0,
                    offset_topic=0,
                    limit=100,
                    q=""
                ))
                msg_map = {m.id: m for m in result.messages}
                # Build sender lookup from result.users and result.chats
                sender_map = {}
                for u in getattr(result, "users", []):
                    sender_map[u.id] = getattr(u, "first_name", "") or getattr(u, "title", "") or getattr(u, "username", "") or "User"
                for c in getattr(result, "chats", []):
                    sender_map[c.id] = getattr(c, "title", "") or "Chat"
                topics = []
                for t in result.topics:
                    msg = msg_map.get(t.top_message)
                    last_text = ""
                    last_sender = ""
                    last_time = ""
                    if msg:
                        # Handle system/action messages
                        if msg.action:
                            act = msg.action
                            act_type = type(act).__name__
                            if act_type == "MessageActionTopicCreate":
                                last_text = "Topic created"
                            elif act_type == "MessageActionTopicEdit":
                                if act.closed is True:
                                    last_text = "Closed topic"
                                elif act.closed is False:
                                    last_text = "Reopened topic"
                                elif act.title:
                                    last_text = "Renamed topic"
                                elif act.hidden is True:
                                    last_text = "Hidden topic"
                                elif act.hidden is False:
                                    last_text = "Unhidden topic"
                                else:
                                    last_text = "Edited topic"
                            elif act_type == "MessageActionPinMessage":
                                last_text = "Pinned message"
                            elif act_type == "MessageActionChatCreate":
                                last_text = "Group created"
                            elif act_type == "MessageActionChatEditTitle":
                                last_text = "Changed title"
                            elif act_type == "MessageActionChatAddUser":
                                last_text = "Added user"
                            elif act_type == "MessageActionChatDeleteUser":
                                last_text = "Removed user"
                            else:
                                last_text = act_type.replace("MessageAction", "")
                        else:
                            last_text = (msg.message or "").replace("\n", " ").replace("\r", "")
                            if not last_text and msg.media:
                                last_text = "📎 Media"
                        # Get sender name
                        try:
                            if msg.out:
                                last_sender = "You"
                            else:
                                sid = msg.sender_id
                                if not sid and msg.from_id:
                                    sid = getattr(msg.from_id, "user_id", None) or getattr(msg.from_id, "channel_id", None)
                                if sid and sid in sender_map:
                                    last_sender = sender_map[sid]
                                elif sid and sid in self.cached_senders:
                                    last_sender = self.cached_senders[sid]["name"]
                                elif sid:
                                    try:
                                        sender = await self.client.get_entity(sid)
                                        last_sender = getattr(sender, "first_name", "") or getattr(sender, "title", "") or getattr(sender, "username", "") or "User"
                                        self.cached_senders[sid] = {"name": last_sender, "avatar": "", "color": get_avatar_color(last_sender)}
                                    except Exception:
                                        last_sender = chat_title
                                else:
                                    last_sender = chat_title
                        except Exception:
                            pass
                        if msg.date:
                            now = msg.date.now(msg.date.tzinfo) if msg.date.tzinfo else msg.date.now()
                            today = now.date()
                            msg_day = msg.date.date()
                            if msg_day == today:
                                last_time = msg.date.strftime("%H:%M")
                            elif (today - msg_day).days == 1:
                                last_time = "Yesterday"
                            else:
                                last_time = msg.date.strftime("%b %d")
                    topics.append({
                        "id": t.id,
                        "title": getattr(t, "title", "General"),
                        "unread_count": getattr(t, "unread_count", 0),
                        "is_general": getattr(t, "id", 0) == 1,
                        "icon_emoji": "📌" if getattr(t, "pinned", False) else ("💬" if getattr(t, "id", 0) == 1 else "💬"),
                        "icon_color": getattr(t, "icon_color", 0),
                        "pinned": bool(getattr(t, "pinned", False)),
                        "closed": bool(getattr(t, "closed", False)),
                        "last_text": last_text[:60],
                        "last_sender": last_sender,
                        "last_time": last_time,
                        "_sort_date": msg.date if msg else None,
                    })
                # Pinned first, then by latest activity (most recent first)
                topics.sort(key=lambda x: (not x["pinned"], -(x["_sort_date"].timestamp() if x["_sort_date"] else 0)))
                # Remove sort key from output
                for t in topics:
                    t.pop("_sort_date", None)
                # Pre-fetch messages for the first topic in background
                # so they're cached when QML requests them
                if topics:
                    async def prefetch():
                        try:
                            msgs = await self.get_messages_for_chat(chat_id, 50, topic_id=topics[0]["id"])
                            ck = f"{chat_id}_{topics[0]['id']}"
                            import time as _t
                            self.messages_cache[ck] = (msgs, _t.time())
                        except Exception:
                            pass
                    asyncio.create_task(prefetch())
                return {"success": True, "chat_id": chat_id, "topics": topics}
            except Exception as e:
                # Not a forum or topics not supported — return empty gracefully
                return {"success": True, "chat_id": chat_id, "topics": []}

        if action == "dialogs":
            lim = int(cmd_dict.get("limit", 40))
            chats = await self.refresh_dialogs_cache(lim)
            return {"success": True, "chats": chats, "unread_total": self.unread_total}

        elif action == "messages":
            chat_id = cmd_dict.get("chat_id")
            lim = int(cmd_dict.get("limit", 50))
            if not chat_id:
                return {"success": False, "error": "chat_id required"}
            topic_id = cmd_dict.get("topic_id")
            cache_key = f"{chat_id}_{topic_id or '0'}"
            import time as _time
            cached = self.messages_cache.get(cache_key)
            if cached and (_time.time() - cached[1]) < 1.5:
                return {"success": True, "chat_id": chat_id, "messages": cached[0]}
            # Fetch messages first (fast), then merge pinned from cache
            msgs = await self.get_messages_for_chat(chat_id, lim, topic_id=topic_id)
            # Merge pinned from cache (instant if already fetched)
            cid = int(chat_id)
            if cid in self.pinned_cache:
                pinned_msgs = self.pinned_cache[cid]
                if topic_id:
                    tid = int(topic_id)
                    if tid == 1:
                        pinned_msgs = [p for p in pinned_msgs if p.get("reply_to") in (1, None)]
                    else:
                        pinned_msgs = [p for p in pinned_msgs if p.get("reply_to") == tid]
                pinned_ids = set(pm["id"] for pm in pinned_msgs)
                for m in msgs:
                    m["pinned"] = m["id"] in pinned_ids
                existing_ids = set(m["id"] for m in msgs)
                for pm in pinned_msgs:
                    if pm["id"] not in existing_ids:
                        msgs.append(pm)
                msgs.sort(key=lambda m: m["id"], reverse=True)
            # Fetch pinned in background if not cached (will be ready on next refresh)
            else:
                asyncio.create_task(self.get_pinned_messages(chat_id))
            self.messages_cache[cache_key] = (msgs, _time.time())
            return {"success": True, "chat_id": chat_id, "messages": msgs}

        elif action == "send":
            chat_id = cmd_dict.get("chat_id")
            text = cmd_dict.get("text", "")
            topic_id = cmd_dict.get("topic_id")
            reply_to = cmd_dict.get("reply_to")
            return await self.send_message_to_chat(chat_id, text, topic_id=topic_id, reply_to=reply_to)

        elif action in ("send_file", "send_media"):
            chat_id = cmd_dict.get("chat_id")
            file_path = cmd_dict.get("file_path", "")
            caption = cmd_dict.get("caption", "") or cmd_dict.get("text", "")
            reply_to = cmd_dict.get("reply_to")
            topic_id = cmd_dict.get("topic_id")
            return await self.send_file_to_chat(chat_id, file_path, caption, reply_to=reply_to, topic_id=topic_id)

        elif action == "download_media":
            chat_id = cmd_dict.get("chat_id")
            msg_id = cmd_dict.get("message_id")
            media_type = cmd_dict.get("media_type", "video")
            if not chat_id or not msg_id:
                return {"success": False, "error": "chat_id and message_id required"}
            try:
                cid = int(chat_id)
                mid = int(msg_id)
                entity = await self.client.get_entity(cid)
                msg = await self.client.get_messages(entity, ids=mid)
                if not msg or not msg.media:
                    return {"success": False, "error": "No media in message"}
                ext = ".mp4" if media_type == "video" else (".jpg" if media_type == "photo" else "")
                target_file = os.path.join(MEDIA_DIR, f"{media_type}_{mid}_{cid}{ext}")
                if os.path.exists(target_file) and os.path.getsize(target_file) > 0:
                    return {"success": True, "file_path": target_file, "chat_id": cid, "message_id": mid, "media_type": media_type}
                path = await self.client.download_media(msg.media, file=target_file)
                if path and os.path.exists(path):
                    try:
                        os.chmod(path, 0o600)
                    except Exception:
                        pass
                    return {"success": True, "file_path": path, "chat_id": cid, "message_id": mid, "media_type": media_type}
                return {"success": False, "error": "Failed to download media"}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "open_external":
            file_path = cmd_dict.get("file_path", "")
            app = cmd_dict.get("app", "xdg-open")
            if not file_path or not os.path.exists(file_path):
                return {"success": False, "error": "File does not exist"}
            try:
                import subprocess
                cmd = ["mpv", file_path] if app == "mpv" else ["xdg-open", file_path]
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return {"success": True, "file_path": file_path, "app": app}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "mark_read":
            chat_id = cmd_dict.get("chat_id")
            topic_id = cmd_dict.get("topic_id")
            return await self.mark_chat_read(chat_id, topic_id=topic_id)

        elif action == "start_qr":
            if await self.client.is_user_authorized():
                return {"success": True, "already_logged_in": True}
            try:
                self.qr_login_obj = await self.client.qr_login()
                img = qrcode.make(self.qr_login_obj.url)
                img.save(QR_PATH)
                try:
                    os.chmod(QR_PATH, 0o600)
                except Exception:
                    pass
                asyncio.create_task(self.wait_for_qr())
                return {"success": True, "qr_path": QR_PATH, "url": self.qr_login_obj.url}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "send_code":
            phone = cmd_dict.get("phone", "").strip()
            self.phone_number = phone
            try:
                res = await self.client.send_code_request(phone)
                self.phone_code_hash = res.phone_code_hash
                return {"success": True, "phone": phone}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "submit_code":
            code = cmd_dict.get("code", "").strip()
            password = cmd_dict.get("password", "").strip()
            try:
                if self.phone_number and self.phone_code_hash:
                    await self.client.sign_in(self.phone_number, code, phone_code_hash=self.phone_code_hash)
                    asyncio.create_task(self.refresh_dialogs_cache())
                    return {"success": True}
                else:
                    return {"success": False, "error": "No phone number requested"}
            except types.errors.SessionPasswordNeededError:
                if password:
                    await self.client.sign_in(password=password)
                    asyncio.create_task(self.refresh_dialogs_cache())
                    return {"success": True}
                return {"success": False, "requires_password": True}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "logout":
            try:
                await self.client.log_out()
                self.dialogs_cache = []
                self.unread_total = 0
                return {"success": True}
            except Exception as e:
                return {"success": False, "error": str(e)}

        elif action == "stop":
            self.running = False
            return {"success": True}

        return {"success": False, "error": f"Unknown action: {action}"}

    async def wait_for_qr(self):
        if not self.qr_login_obj:
            return
        try:
            await self.qr_login_obj.wait(timeout=120)
            print("QR code successfully scanned and authorized!")
            asyncio.create_task(self.refresh_dialogs_cache())
        except Exception as e:
            print(f"QR login wait error or expired: {e}")

    async def handle_client(self, reader, writer):
        try:
            data = await reader.readuntil(b"\n")
            line = data.decode("utf-8").strip()
            if line:
                cmd_dict = json.loads(line)
                response = await self.execute_command(cmd_dict)
                writer.write(json.dumps(response).encode("utf-8") + b"\n")
                await writer.drain()
        except Exception as e:
            try:
                writer.write(json.dumps({"success": False, "error": str(e)}).encode("utf-8") + b"\n")
                await writer.drain()
            except Exception:
                pass
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

if __name__ == "__main__":
    daemon = TelegramBackend()
    try:
        asyncio.run(daemon.start())
    except KeyboardInterrupt:
        pass
