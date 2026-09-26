# Setup and local data

## Accounts

Open **Accounts** in DankChat to link or disconnect a service. Both use QR
linking; Telegram may also ask for your account password. Disabling a provider
pauses it and preserves its session. Disconnecting signs out the DankChat device
and removes its local downloaded media; it doesn't delete your conversations.

The installer adds a desktop launcher, `dankchat-whatsapp.service` for the
original account, and `dankchat-whatsapp@.service` for additional accounts. WhatsApp
sync starts after linking and stops when WhatsApp or DankChat is disabled.
Rerun `python3 scripts/setup` after upgrading from a single-account
version to install the additional-account unit template.

Telegram uses the upstream public application credentials. To use your own,
set `api_id` and `api_hash` in `$XDG_CONFIG_HOME/dankchat/telegram/config.json`.

Choose **Add another account** and a name, then link it by QR. Names appear in
the vertically stacked account buttons; **All** combines them. Rename an account
under **Accounts** at any time. Names are labels, not routing IDs: identical chat
IDs in different accounts remain separate. Existing sessions retain their paths;
additional sessions use private UUID subdirectories. Disconnecting keeps the named
slot so it can be linked again.

## Settings, search and notifications

The gear opens app settings. The magnifier and gallery icons beside the chat name
open message search and media browsing. Select a result to jump to its original
context, or **Load more** to browse older results. WhatsApp searches the local
mirror; Telegram searches server history. Right-click your own message text to
edit it; service time limits and permissions apply.

Read synchronization can be enabled per account. DankChat marks messages read
when the latest conversation is visible, not while browsing search results,
settings or older history. Reads from other devices are picked up on refresh
(Telegram also emits immediate read events). Synchronization needs a connection;
it is not an instantaneous cross-device guarantee.

Notifications default to off. Select all messages, mentions only (Telegram), or
off globally and override per account or via a chat's context menu. Message
previews, sound and suppression for the open chat are separate options. WhatsApp
stays silent under a mentions-only policy unless that account/chat overrides it.
Only new activity observed after startup creates notifications, avoiding a burst
for previously unread chats. Delivery uses the desktop notification service.

`Ctrl+K` focuses chat search, `Ctrl+F` opens message search, `Alt+Up/Down` changes
chat, `Ctrl+R` replies to the latest loaded message, and Escape closes the current
view. The dropdown's focus-loss behavior is configurable; clicking outside still
closes it.

The installed version and local Git changes are shown under **Version and updates**.
Automatic GitHub checks are cached for 24 hours; **Check for updates** forces a
fresh check. Releases open on GitHub. DankChat does not automatically install code.
**Save diagnostic report** exports versions, connection flags and bounded request
timings, without message bodies, account names/IDs, credentials or attachment paths.

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
an album. A failed send stops the batch and keeps the remaining files in that
chat’s attachment draft. Dropdown and window share these drafts; a service restart
or plugin reload discards them.

If the clipboard offers both an unusable file link and image data, DankChat uses
the image data. BMP and TIFF images are converted to PNG.

Telegram shows online/last-seen information when privacy settings allow it. Both
services show incoming typing and voice-recording activity when available; the
WhatsApp helper does not expose online/last-seen information.

Temporary connection errors preserve the chat list and text drafts. A stopped
bridge is restarted automatically, with a manual **Reconnect** button available.
Interrupted sends are never retried automatically: check the conversation first.
The **Accounts** page shows connection/sync-service state and the last successful
chat-list check. `dms ipc call dankChat diagnostics` returns recent request timing
and outcomes without message text, chat IDs or file paths.

Voice recording uses your default microphone. Check that input in your desktop
audio settings if recordings are silent. Stop the recording to listen before
sending. Closing both chat surfaces stops capture and keeps a preview; switching
to another chat or reloading DankChat discards it.

## Local files

| Data | Directory |
| --- | --- |
| Account names and identities | `$XDG_CONFIG_HOME/dankchat/accounts.json` |
| Telegram session and configuration | `$XDG_CONFIG_HOME/dankchat/telegram` |
| Telegram media cache | `$XDG_CACHE_HOME/dankchat/telegram` |
| WhatsApp session and helper data | `$XDG_STATE_HOME/dankchat/whatsapp` |
| Temporary recordings, clipboard images and runtime lock | `$XDG_RUNTIME_DIR/dankchat` |

Standard XDG defaults apply. DMS plugin settings are separate from account sessions.

## Launcher shortcuts

```sh
dms ipc call dankChat open
dms ipc call dankChat accounts
dms ipc call dankChat settings
dms ipc call dankChat close
```

## Removing DankChat

To revoke the linked sessions, use **Disconnect account** first. Otherwise,
uninstalling preserves account data.

Disable the plugin and remove its bar widget. Stop `dankchat-whatsapp.service`,
stop any `dankchat-whatsapp@*.service` instances, remove both unit files from your systemd user configuration and run
`systemctl --user daemon-reload`. Remove the plugin directory or development
symlink and the `dankchat.desktop` launcher from your local applications directory.


## Responsiveness

Recent message lists for up to 12 chats are kept in memory while DankChat runs.
Opening a cached chat displays it immediately and refreshes it in the background.
Switching chats returns to the latest message, including after media changes
height; scrolling up deliberately keeps your reading position.

Visible media is prioritized. Automatic downloads respect selected categories
and the file size limit (25 MB by default); unknown sizes need a manual click.
The media cache defaults to 512 MB and 30 days, cleaned hourly while running.
The open conversation's media is protected, so the limit can be exceeded by those
files. Manual cleanup also preserves open media, account data and user originals.
WhatsApp downloads use a read-only CDN path and no longer stop synchronization.
A rejected/expired download is distinguished from a transient connection failure;
opening the file on the phone or asking for a fresh copy may be necessary.
Failed automatic downloads are not repeatedly retried; use the download button.

Telegram allows two downloads at once; WhatsApp
uses one to limit contention on its local store. Automatic media loading pauses
while sending. Downloads no longer share DankChat's send queue, though WhatsApp's
underlying store/network can still serialize operations.

Each confirmed attachment is shown immediately with a private local preview,
without waiting for the whole batch or downloading the upload again. These copies
are bounded to 128 confirmed messages and 256 MB per account, live under the
runtime directory, and are removed when the provider closes. No message is shown
as sent before the provider confirms it.
