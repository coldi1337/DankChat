# DankChat

Telegram and WhatsApp in one native DankMaterialShell plugin. One bar widget
opens a compact chat dropdown; the same conversation can open in a separate
resizable window. Both services share a WhatsApp-inspired layout and DMS styling.
There is no Electron runtime or embedded browser.

**Development version. Not submitted to the DMS registry.** Real-account
acceptance testing is still required. The current implementation is the first
shared client, not full feature parity with both upstream applications.

## Implemented

- A composite DMS plugin with one background owner and widgets on multiple bars.
- One chat list, with All / Telegram / WhatsApp filters and local chat search.
- Text history, text sending, replies, one-file attachment sending, and local
  image display/external media opening through a common interface.
- Chat selection and separate in-memory drafts survive switching between the
  dropdown and app window. Drafts do not yet survive a shell restart.
- Telegram QR login, including the additional account password when required.
- WhatsApp terminal QR linking and an isolated systemd user sync service.
- Telegram read receipts off by default; WhatsApp opening acknowledges the
  local badge without sending a receipt.
- Optional German UI translations and an isolated sample-data mode with
  sending disabled.

## Requirements

- DMS 1.6.1 or newer, Quickshell, Python 3.10+.
- Telegram: Telethon, qrcode, Pillow (installed into a project virtualenv).
- WhatsApp: **wacli 0.17.1** at `~/.local/bin/wacli`, systemd user services.
- WhatsApp linking: `xdg-terminal-exec`, Ghostty, foot, or kitty.
- Qt Quick Dialogs for the attachment picker; a desktop media viewer for
  external opening.

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

- Left-click the widget: dropdown.
- Right-click the widget, or launch **DankChat**: separate app window.
- Open-in-new button: expand the current dropdown conversation into the app.
- Enter: send; Shift+Enter: newline.
- Accounts button: link Telegram or WhatsApp. Complete linking on your phone.

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

## Current limits / release gate

The following are not yet finished or verified:

- Real-account login, live incoming messages, sending and attachment acceptance
  for both services; reconnect after network loss and suspend.
- Telegram topic navigation, editing, forwarding, pinning and reactions in the
  shared UI.
- WhatsApp voice recording, group mentions, richer media playback and multiple
  account setup in the shared UI.
- On-demand media download/gallery parity and persistent drafts.
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

The DMS integration was developed with substantial AI assistance. Publication
and registry review must disclose this and must not imply that unperformed
human or real-account tests have passed.
