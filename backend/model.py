"""Provider-neutral values. Message and account IDs remain opaque strings."""
from datetime import datetime, timezone
import json


def key(provider, account, chat):
    return json.dumps([provider, str(account or ""), str(chat)], separators=(",", ":"))


def timestamp(value):
    if isinstance(value, (int, float)):
        return int(value)
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return int(parsed.replace(tzinfo=parsed.tzinfo or timezone.utc).timestamp())
    except (TypeError, ValueError):
        return 0


def chat(provider, raw):
    telegram = provider == "telegram"
    account = "" if telegram else str(raw.get("account", ""))
    ident = str(raw["id"] if telegram else raw["jid"])
    last = raw.get("last_message", {}) if telegram else {}
    unread = raw.get("unread_count", 0) if telegram else raw.get("notification_unread", raw.get("unread", 0))
    return {
        "key": key(provider, account, ident), "provider": provider,
        "account": account, "id": ident,
        "name": str(raw.get("title" if telegram else "name", ident)),
        "preview": str(last.get("text", "") if telegram else raw.get("preview", "")),
        "timestamp": timestamp(last.get("timestamp", last.get("date", "")) if telegram else raw.get("timestamp", 0)),
        "unread": max(0, int(unread or 0)), "avatar": raw.get("avatar", ""),
        "forum": bool(raw.get("is_forum", False)),
        "pinned": bool(raw.get("pinned", False)),
        "group": bool(raw.get("is_group", False) if telegram else raw.get("kind") == "group"),
    }


def message(provider, raw):
    telegram = provider == "telegram"
    return {
        "id": str(raw.get("id", "")),
        "text": str(raw.get("text", "")),
        "sender": str(raw.get("sender_name" if telegram else "sender", "")),
        "out": bool(raw.get("out" if telegram else "from_me", False)),
        "timestamp": timestamp(raw.get("timestamp", raw.get("date", 0))),
        "time": str(raw.get("time", "")),
        "mediaType": str(raw.get("media_type", "")),
        "mediaPath": str(raw.get("media_path" if telegram else "local_path", "")),
        "mediaThumb": str(raw.get("media_thumb", "")),
        "mimeType": str(raw.get("mime_type", "")),
        "filename": str(raw.get("filename", "") or (raw.get("media_info") or {}).get("file_name", "")),
        "replyId": str(raw.get("reply_to_msg_id" if telegram else "quoted_id", "") or ""),
        "replyText": str(raw.get("reply_to_text" if telegram else "quoted_text", "")),
        "edited": bool(raw.get("is_edited" if telegram else "edited", False)),
        "deliveryPartial": bool(raw.get("delivery_partial", False)),
        "deliveryStatus": str(raw.get("status", "sent" if raw.get("out") else "") if telegram else raw.get("delivery_status", "sent" if raw.get("from_me") else "")),
    }


def messages(provider, rows):
    # Both helpers return newest first. ListView displays oldest first at the top.
    return sorted((message(provider, raw) for raw in reversed(rows)), key=lambda item: item["timestamp"])
