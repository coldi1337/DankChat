# Third-party notices

DankChat's original code and documentation are licensed under the [MIT License](LICENSE),
Copyright (c) 2026 coldi1337. The following components retain their own copyright
notices and licenses.

| Component | Copyright | License |
| --- | --- | --- |
| [OmarGram](https://github.com/JoeJoeflyn/omargram), adapted Telegram client | Copyright (c) 2026 JoeJoeflyn | [MIT](vendor/telegram/LICENSE) |
| [OmaWhatsApp](https://github.com/MoizIbnYousaf/Omarchy-Whatsapp), adapted helper, assets and tests | Copyright (c) 2026 MoizIbnYousaf | [MIT](vendor/whatsapp/LICENSE) |
| [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell), test manifest schema | Copyright (c) 2025 Avenge Media LLC | [MIT](tests/DMS-LICENSE) |
| Unicode Emoji and CLDR data | Copyright © Unicode, Inc. | [Unicode License v3](data/unicode/LICENSE) |

## Adapted clients

`vendor/telegram/telegram_client.py` and `vendor/whatsapp/bin/` contain adapted
upstream code. Changes include DankChat paths and naming, DMS integration,
message metadata and shared-client features. The WhatsApp interface also informed
DankChat's chat-list and composer layout.

Exact source revisions are recorded in [docs/upstream.json](docs/upstream.json).
The [upstream WhatsApp notices](vendor/whatsapp/THIRD_PARTY_NOTICES.md) are retained.

## Test schema

`tests/plugin-schema.json` comes from DankMaterialShell's
[plugin development skill](https://github.com/AvengeMedia/DankMaterialShell/tree/master/.agents/skills/dms-plugin-dev).
Its license is retained in `tests/DMS-LICENSE`.

## Emoji data

`emoji-data.js` is generated from Unicode Emoji 17.0 and Unicode CLDR 48
English/German annotations. The full Unicode License v3 is retained in
`data/unicode/LICENSE`; source URLs and hashes are in
[data/unicode/sources.json](data/unicode/sources.json).

## External dependencies

DMS/Quickshell, Telethon, qrcode, Pillow, wacli, Qt Multimedia, FFmpeg and
wl-clipboard are installed separately and remain subject to their respective
licenses. DankChat does not distribute their binaries.
