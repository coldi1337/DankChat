# DankChat

Telegram and WhatsApp, right in [DankMaterialShell](https://danklinux.com/).
Check a conversation from the bar or open a regular window when you need more
room. Built with native QML widgets, without Electron or an embedded browser.

![DankChat preview](docs/preview.png)

## What it does

- Both services in one chat list, with search, pinned chats and an unread filter.
- Replies, emoji reactions and message deletion, including “for everyone” where supported.
- Paste screenshots, select multiple attachments and save received media.
- View images with zoom, watch videos and listen to voice messages with seeking
  and playback speed controls.
- Record a voice message, listen back, then send it or discard it.
- Typing indicators for both services, plus Telegram online and last-seen status.
- QR sign-in, DMS themes, and English and German interfaces.

## Install

You'll need **DMS 1.6.1+**, Quickshell, **Python 3.10+** and systemd user services.
For media, install Qt Multimedia and image-format plugins (`qt6-multimedia-ffmpeg`
and `qt6-imageformats` on Arch). Clipboard attachments need **wl-clipboard**.
Voice recording needs **FFmpeg** with libopus and PulseAudio input, using either
PulseAudio or PipeWire with `pipewire-pulse`.

Install DankChat from **DMS Settings → Plugins**, then open its installed
folder and run:

```sh
sh scripts/setup-telegram
python3 scripts/install-local
```

Run both commands even if you only use WhatsApp: they set up the Python
libraries, QR linking, background sync and desktop launcher. DMS downloads the
plugin but doesn't install these dependencies for you.

For WhatsApp, install [wacli 0.17.1](https://github.com/openclaw/wacli/releases/tag/v0.17.1)
at `~/.local/bin/wacli`. Choose the build for your system and check it against
the release's `checksums.txt`.

Enable DankChat, add its bar widget, then open **Accounts** to link Telegram
or WhatsApp.

Prefer a Git checkout? Clone this repository and run the same two setup commands
from there. The installer links the checkout into DMS, so keep that folder in place.

## Everyday use

**Left-click** the widget for the dropdown; **right-click** for the app window.
Clicking outside closes the dropdown. The expand button moves the conversation
into the app window, keeping your draft.

Right-click a chat to pin it or mark it as read. Use the message actions to
reply, react or delete. **Enter** sends; **Shift+Enter** adds a line break.
The microphone button starts a recording, with a preview before sending.

Automatic Telegram read marking is off by default. Enable **Telegram read
receipts** in plugin settings if you want opening a chat to mark it as read.
For WhatsApp, opening a chat clears DankChat's badge; **Mark as read** syncs the
read state with WhatsApp. The bar counter counts unread chats, not messages.

If the app window always floats, see the [Hyprland rule](integration/hyprland.lua)
for an exception using the title `DankChat`.

## A few limits

DankChat covers everyday messaging, but doesn't yet support Telegram topics,
message editing or forwarding, or multiple accounts per service. Older history
is limited, and drafts are lost when DankChat restarts.

WhatsApp online/last-seen status isn't exposed by the current backend. Some
stickers and media formats need an external viewer; attachments that haven't
synced to the linked device may be unavailable. Read indicators depend on the
receipt data available to DankChat.

Attachments are sent individually, up to 10 at a time. Voice recordings stop
after five minutes or when you close the chat; switching chats discards the
recording. If a send fails, check the conversation before trying again.

## More details

- [Setup, local data and troubleshooting](docs/usage.md)
- [Development and testing](docs/development.md)
- [Test results](docs/validation.md)

## License and credits

[MIT](LICENSE) © 2026 coldi1337. DankChat builds on
[OmarGram](https://github.com/JoeJoeflyn/omargram) and
[OmaWhatsApp](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp).
Their notices and the Unicode data license are preserved in
[Third-party notices](THIRD_PARTY_NOTICES.md).

Developed with AI assistance.
