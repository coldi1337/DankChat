# Third-party software

DankChat is an independent DMS integration built on two MIT-licensed projects:

- [OmarGram](https://github.com/JoeJoeflyn/omargram), by JoeJoeflyn.
  `vendor/telegram/telegram_client.py` retains the Telegram chat, message,
  and media operations. Directory roots and internal names use DankChat,
  and desktop refresh/notification commands are adapted for DMS. QR linking
  is implemented separately in `backend/qr_login.py`. Numeric message/chat
  timestamps were added for consistent chronological ordering.
- [OmaWhatsApp](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp), by
  MoizIbnYousaf. Its helper and asset module are adapted under
  `vendor/whatsapp/bin/whatsapp_client.py` and `whatsapp_assets.py`.
  Internal identifiers, user-facing branding and local staging names use
  neutral provider names or DankChat; wacli protocol arguments are retained.
  Three Python backend test files are included and follow the renamed imports.
  One Omarchy installer test is explicitly skipped because that installer
  is not included in DankChat.

Exact upstream revisions are recorded in [docs/upstream.json](docs/upstream.json).
Both original MIT notices are retained alongside the source. The upstream
WhatsApp third-party notice is also retained there.

The common DMS interface is implemented in `ChatView.qml`, with the WhatsApp
client's chat-rail/conversation/composer layout informing both services.

The DMS manifest schema in `tests/plugin-schema.json` comes from
[DankMaterialShell's plugin development skill](https://github.com/AvengeMedia/DankMaterialShell/tree/master/.agents/skills/dms-plugin-dev).
It is used for development validation, not included as an application service.

Runtime dependencies are installed separately: Telethon, qrcode, Pillow, and
wacli. Their licenses continue to apply. DankChat does not bundle a wacli binary.
