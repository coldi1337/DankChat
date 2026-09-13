# DankChat

Telegram and WhatsApp in one native DankMaterialShell plugin. One bar widget
opens a compact chat dropdown; the same conversation can open in a separate
resizable window. Both services share a WhatsApp-inspired layout and DMS styling.
There is no Electron runtime or embedded browser.

**Development version. Not submitted to the DMS registry.** Real-account
acceptance testing is still required. A recurring whole-shell crash remains under
investigation; the local development plugin is enabled for user-triggered reproduction. The current implementation is the first
shared client, not full feature parity with both upstream applications.

## Implemented

- A composite DMS plugin with one background owner and widgets on multiple bars.
- One chat list, with All / Telegram / WhatsApp filters and local chat search.
  The **Unread** toggle shows only unread chats; its count is the number of
  unread chats matching the current provider and search. Click again to show all
  matching chats. Marking a chat read removes it from this filtered list without
  closing the open conversation.
- Text history, text sending, replies, one-file attachment sending, and local
  automatic media loading in the open chat, inline images/stickers, and video/audio playback.
- Clickable web links and distinct incoming/outgoing message bubbles.
- A themed emoji picker beside the attachment button with the complete Unicode
  Emoji 17.0 catalog (3,953 entries, including skin tones and compound sequences).
  Search German/English names and keywords offline, or browse categories.
  Inserts at the cursor or replaces selected text. Glyph rendering depends on
  the installed emoji font; newer emoji may require a font update.
- Pinned chats first, with Pin/Unpin in the chat context menu.
- Right-click a chat and choose **Mark as read** to explicitly update its read
  state through Telegram or WhatsApp. WhatsApp synchronizes the chat read state;
  this is separate from sender-visible per-message read receipts.
- A nonmodal dropdown that allows interacting with other windows.
- Chat selection and separate in-memory drafts survive switching between the
  dropdown and app window. Drafts do not yet survive a shell restart.
- Telegram QR login, including the additional account password when required.
- WhatsApp QR linking inside the account dialog and an isolated systemd user sync service.
- Explicit sign-out for either account, with confirmation and local cache cleanup.
- Telegram read receipts off by default; WhatsApp opening acknowledges the
  local badge without sending a receipt.
- Optional German UI translations and an isolated sample-data mode with
  sending disabled.

## Requirements

- DMS 1.6.1 or newer, Quickshell, Python 3.10+.
- Telegram: Telethon, qrcode, Pillow (installed into a project virtualenv).
- WhatsApp: **wacli 0.17.1** at `~/.local/bin/wacli`, systemd user services.
- Both QR login flows use qrcode and Pillow from the project virtualenv.
- The built-in DMS file browser for attachments and media export; a desktop media viewer for
  external opening. Qt Multimedia and image format plugins enable inline media
  (Arch: `qt6-multimedia-ffmpeg qt6-imageformats`). Animated Telegram vector
  stickers are not rendered inline; unsupported files can open externally.

Tested development environment: Arch Linux, Hyprland 0.56.2, DMS 1.6.1.
Other compositor/distribution combinations are not yet verified.

### Tiling window

The app uses a regular, resizable Wayland window in addition to the dropdown.
If your compositor has a rule that floats all DMS windows, give the exact title
`DankChat` an exception. A Hyprland Lua example is provided in
`integration/hyprland.lua`; load it after the general DMS window rules.

## Local development installation

From this checkout:

```sh
sh scripts/setup-telegram
python3 scripts/install-local
```

The installer links the checkout under
`~/.config/DankMaterialShell/plugins/DankChat`, installs the WhatsApp user
unit, and adds a DankChat desktop launcher. It does not replace your DMS bar
configuration or install wacli. Enable DankChat in DMS Settings → Plugins,
then add its widget to your DankBar layout.

Download the matching wacli 0.17.1 build from the
[official release](https://github.com/openclaw/wacli/releases/tag/v0.17.1),
verify its checksum against that release's `checksums.txt`, and place the
executable at `~/.local/bin/wacli`.

## Using DankChat

- Left-click the widget: toggle the compact dropdown for quick chats. A click outside closes it; the normal app window stays open until closed.
- Right-click the widget: open the same conversation in a normal, resizable, tiling-capable app window. The desktop launcher opens this window too.
- Open-in-new button: expand the current dropdown conversation into the app.
- Enter: send; Shift+Enter: newline.
- Click a quoted reply to jump to its original message. Older originals open a small history context; the down-arrow returns to the latest messages. Deleted or unsynchronized originals may be unavailable.
- Images: click to enlarge, wheel or +/− to zoom, drag to pan, double-click to reset/toggle zoom.
- Videos: expand button opens a large player inside the current window; playback continues.
- Accounts button: link Telegram or WhatsApp directly using the displayed QR code. Complete linking on your phone; no terminal is needed.
- Connected accounts offer **Disconnect account**. After confirmation, DankChat revokes its session and removes local cached chats, media and drafts. Phone/cloud messages remain intact; reconnecting needs a fresh QR scan. A failed remote logout preserves the local session. Disabling a provider in settings only pauses it and preserves the session.

IPC entry points:

```sh
dms ipc call dankChat open
dms ipc call dankChat accounts
dms ipc call dankChat close
```

Both providers are enabled by default, but no Telegram connection is made until
linking is requested or a DankChat session already exists. The WhatsApp sync
unit starts only after a linked session is found. Disabling WhatsApp or DankChat
stops its sync; existing account sessions are preserved.

## Data and behavior

Sessions are separate from the original clients:

- Telegram: `$XDG_CONFIG_HOME/dankchat/telegram` and
  `$XDG_CACHE_HOME/dankchat/telegram`.
- WhatsApp: `$XDG_STATE_HOME/dankchat/whatsapp`.
- Runtime lock: `$XDG_RUNTIME_DIR/dankchat`.

Standard XDG defaults apply when variables are missing or relative. Session
directories are private to your user. The UI passes passwords and message
payloads over a private stdin pipe; the inherited wacli helper still passes
message arguments to the wacli executable. Nothing is stored in DMS plugin
preferences except ordinary settings. Upstream session files are not imported.

Telegram currently uses the upstream default public client application credentials.
A custom `api_id` / `api_hash` can be supplied in
`$XDG_CONFIG_HOME/dankchat/telegram/config.json`; this is separate from DMS settings.

No automatic resend follows a failed or timed-out send. Check the conversation
before retrying, because the remote service may already have accepted it.

WhatsApp delivery/read indicators use signed live receipt events received only on
loopback (`127.0.0.1`), with no message bodies and no external forwarding. Old
messages without recorded receipts show only the sent state. A group receipt
means at least one participant has confirmed it; the tooltip states this.
Telegram uses its server-provided sent/read status. Receiving these updates does
not enable outgoing read receipts.

Attachment selection and **Save media as…** use the DMS file browser embedded
in the chat window, including DMS colors and overwrite confirmation. This avoids
the native GTK dialog after a local GTK/GVFS crash. Closing it cancels selection; choosing an attachment still requires the separate
Send confirmation. The download icon on loaded media saves a copy to your chosen
location. Media in the current chat loads automatically, newest first, one file
at a time. Closing both surfaces stops further automatic downloads; failed
downloads can be retried manually. The search field offers an X to clear its filter.

## Current limits / release gate

The following are not yet finished or verified:

- Real-account login, live incoming messages, sending and attachment acceptance
  for both services; reconnect after network loss and suspend.
- Telegram topic navigation, editing, forwarding, message pinning and reactions in the
  shared UI.
- WhatsApp voice recording, group mentions and multiple
  account setup in the shared UI.
- Media format/gallery parity and persistent drafts.
- Full keyboard/accessibility checks, vertical bars, additional monitor layouts,
  and a clean installation test on another checkout.

Registry submission follows working real-account tests, review, and a
representative screenshot containing only synthetic conversations.

## Validation

```sh
.venv/bin/pip install jsonschema
sh scripts/test
```

This runs provider routing/privacy tests, retained upstream Python backend
tests, QML syntax parsing and the DMS manifest schema. It does not send messages
or use real account databases. See [docs/validation.md](docs/validation.md) for
the actual tested state and outstanding checks.

## Uninstall

Disable DankChat in DMS and remove its widget from DankBar. Stop
`dankchat-whatsapp.service`, remove its user unit and reload systemd, then remove
the development symlink and `dankchat.desktop` launcher. Keep the checkout if
you want to continue development. Account data is deliberately preserved;
logging out or deleting sessions is a separate action.

## Credits and license

MIT. Built on [OmarGram](https://github.com/JoeJoeflyn/omargram) and
[OmaWhatsApp](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp).
See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[docs/upstream.json](docs/upstream.json).

The DMS integration was developed with AI assistance. See the
[validation record](docs/validation.md) for completed checks and remaining
acceptance tests.
