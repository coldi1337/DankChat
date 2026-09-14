# Setup and local data

## Accounts

Open **Accounts** in DankChat to link or disconnect a service. Both use QR
linking; Telegram may also ask for your account password. Disabling a provider
pauses it and preserves its session. Disconnecting signs out the DankChat device
and removes its local account cache; it doesn't delete your conversations.

The installer adds a desktop launcher and `dankchat-whatsapp.service`. WhatsApp
sync starts after linking and stops when WhatsApp or DankChat is disabled.

Telegram uses the upstream public application credentials. To use your own,
set `api_id` and `api_hash` in `$XDG_CONFIG_HOME/dankchat/telegram/config.json`.

## Messages and media

Telegram's **Mark as read** action works even when automatic read marking is
disabled. WhatsApp read-state synchronization and sender-visible message receipts
are separate. Historical WhatsApp messages without recorded receipts may show
only “sent”; a group receipt means at least one participant confirmed it.

Telegram supergroups and channels only support deleting messages for everyone.
WhatsApp deletion for everyone is offered for your own messages. Service permissions
and time limits still apply; DankChat won't retry with a different deletion scope.

Clipboard images are limited to 20 MB, other attachments to 100 MB each. Files
are sent sequentially with the typed caption on the first file, rather than as
an album. A failed send stops the batch.

Voice recording uses your default microphone. Check that input in your desktop
audio settings if recordings are silent. Stop the recording to listen before
sending. Closing both chat surfaces stops capture and keeps a preview; switching
to another chat or reloading DankChat discards it.

## Local files

| Data | Directory |
| --- | --- |
| Telegram session and configuration | `$XDG_CONFIG_HOME/dankchat/telegram` |
| Telegram media cache | `$XDG_CACHE_HOME/dankchat/telegram` |
| WhatsApp session and helper data | `$XDG_STATE_HOME/dankchat/whatsapp` |
| Temporary recordings, clipboard images and runtime lock | `$XDG_RUNTIME_DIR/dankchat` |

Standard XDG defaults apply. DMS plugin settings are separate from account sessions.

## Launcher shortcuts

```sh
dms ipc call dankChat open
dms ipc call dankChat accounts
dms ipc call dankChat close
```

## Removing DankChat

To revoke the linked sessions, use **Disconnect account** first. Otherwise,
uninstalling preserves account data.

Disable the plugin and remove its bar widget. Stop `dankchat-whatsapp.service`,
remove its unit from your systemd user configuration and run
`systemctl --user daemon-reload`. Remove the plugin directory or development
symlink and the `dankchat.desktop` launcher from your local applications directory.
