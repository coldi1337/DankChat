# Changelog

## 0.6.1 — 2026-10-29

### Fixed

- Restore attachment and save dialogs on DMS 2.0 by recognizing the renamed
  `DCommon` file-picker module, while retaining the DMS 1.6.x fallbacks.
- Avoid QML binding loops in the message placeholder and when a file-picker
  error closes its dialog.
- Keep the isolated UI and service tests working with both DMS module names
  and runtimes that do not allow replacing QML methods.

Thanks to [@junamat](https://github.com/junamat) for
[PR #3](https://github.com/coldi1337/DankChat/pull/3).

The minimum DMS version and external dependencies are unchanged. The Telegram
application-ID issue remains open, as documented in 0.6.0.

## 0.6.0 — 2026-10-06

### Fixed

- Refresh only the account (and chat) that reported an update instead of every
  account of the service, and bundle bursts of updates from busy groups.
- Serve the Telegram chat list from cache until an update or a write changes it,
  refetching at most every 3 seconds and at least every 5 minutes. Refresh
  failures are now shown instead of silently keeping an outdated list.
- Back off after Telegram refresh failures and respect reported flood waits.
  Concurrent writes and cancelled fetches no longer leave the chat cache clean
  when another refresh is still needed.
- Stop the 2-second account refresh once the window is closed while the account
  view was open.
- Chats beyond the 40 most recent no longer fail with “Select an existing
  Telegram chat first” for a few seconds after sending or deleting.
- Retry automatic read synchronization when a read is still running or fails, so
  messages arriving meanwhile are also marked read on other devices.
- A failed edit request while reconnecting no longer blocks sending until DMS restarts.
- Cache WhatsApp health checks instead of starting `wacli doctor` and `systemctl`
  on every refresh.
- Logging out an additional account no longer shows the original account as
  disconnected; the reconnect notice clears after the next action.
- Show accurate errors when sending is busy or more than 10 attachments are chosen.
- An expired WhatsApp QR login is reported as expired on Python 3.10.
- Add missing German translations for service errors and the new controls.

### Improved

- Day headings (“Today”, “Yesterday”, date) in conversations and the time of the
  latest activity in the chat list.
- Telegram conversations reload from a local cache that update events clear,
  instead of fetching the history from Telegram every five seconds. Reactions by
  others and read receipts of sent messages update through events.
- Press Up in an empty composer to edit your last message; Escape cancels a reply.
- Add missing tooltips and accessible names to chat action buttons.
- Cleanup removes abandoned partial-download directories older than an hour.

### Security and reliability

- Automatic read synchronization in the app window requires the window to be active.
- Ask before opening received documents, including SVG images, externally.
- An attachment whose upload was not confirmed is kept but excluded from the next
  send until it is explicitly included again.
- WhatsApp writes that outlive a request timeout keep sync paused until they finish
  and refresh the conversation when they complete.
- Wait for outstanding WhatsApp writes before logout, shutdown or clearing shared
  temporary files; cancelled writes still waiting their turn are never sent later.
- Previews of sent attachments are stored in the cache directory instead of the
  memory-backed runtime directory, with one shared 256 MB limit for all accounts.
- The receipt webhook only accepts connections from the same user, handles them
  concurrently and times out idle connections.
- Setup verifies wacli against checksums pinned in the repository and installs
  Python dependencies with `--require-hashes`.
- A restarted service waits for its predecessor instead of exiting silently.
- Ask before removing downloaded media.

### Removed

- The unused `link-whatsapp` and `open-link-terminal` scripts, which required wacli 0.17.1.

### Known limitations

- A dedicated Telegram application ID and shared custom credentials for additional
  accounts are deferred. The inherited Telegram Desktop API credentials remain
  the default in this release.
- CPU, battery and network savings have not been measured. Media players are
  still created when their message delegates load.

## 0.5.1 — 2026-09-28

### Fixed

- Fix the blank chat window on newer DMS builds where `FileBrowserContent` was
  removed. The file dialog now selects the modern or legacy native picker at
  runtime, preserving support for older DMS versions (issue #1).
- Preserve the native picker's layout and theming when loading it dynamically.
- Show a clear English/German error if no compatible picker is available, while
  keeping the conversation usable.
- Clear diagnostic-export mode when the file dialog is dismissed.

### Improved

- Support selecting multiple attachments at once in the modern DMS picker.
- Check file-picker components and shared dependencies in `check-environment`,
  and distinguish this file check from a full QML runtime test.
- Extend UI coverage for selection, media/diagnostic export, cancellation,
  missing picker types and layout geometry on both DMS generations.
- Fix the test runner's shutdown path after a QML loading failure and isolate
  its home directory as well as its settings and account data.

### Upgrade notes

Update DankChat and restart DMS. If setup has not been run since upgrading from
0.4, run `python3 scripts/setup` in the plugin folder first. This patch adds no
new dependencies and preserves existing accounts and settings. Restarting DMS
clears drafts held only in memory.

## 0.5.0 — 2026-09-26

### Added

- Multiple Telegram and WhatsApp accounts, with separate sessions, editable names
  and vertically stacked account buttons.
- App settings for read synchronization, notifications, automatic media downloads,
  cache limits and dropdown behavior.
- Message search and media browsing, with pagination and jumps to the original
  conversation. WhatsApp searches the history available on the linked device.
- Editing your own messages, with an edited marker and service-specific limits.
- Notifications with per-account and per-chat overrides, optional previews and
  sound. Mentions-only notifications are supported for Telegram.
- Installed version, GitHub release checks and diagnostic reports that exclude
  messages, account identities, credentials and attachment paths.
- Keyboard shortcuts for chat and message search, switching chats and replying.
- One setup command for Python dependencies, verified wacli installation, desktop
  launcher and background services. Existing compatible wacli builds are retained.

### Improved

- Separate request queues per account let conversation updates continue while
  uploads and media downloads are running. Media caches avoid repeated downloads.
- Sent media appears from the local confirmed attachment while the service catches
  up. Transfer states distinguish uploads, downloads and unconfirmed sends.
- More reliable scrolling to the latest message when opening a chat, including
  when images change the message height after loading.
- Clipboard image handling and attachment errors, including media no longer
  available from WhatsApp.
- Bidirectional read-state synchronization, with automatic marking limited to the
  visible latest conversation. Telegram reads stop at the latest loaded message.
- English and German text throughout the new settings and account views.

### Fixed

- Use DMS's public `DankPopout` API instead of `DankPopoutStandalone`, resolving
  the loading failure reported with DMS Git revision `80060ee` (#1).
- Accept compatible wacli versions from 0.17.1 instead of requiring an exact
  version. The recommended and tested release is now 0.19.0 (#2).
- Download WhatsApp media without interrupting the background sync store.

### Upgrade notes

Update the plugin, run `python3 scripts/setup` in its folder and restart DMS when
ready. The setup adds the service template needed for additional WhatsApp accounts.
Existing accounts and settings are kept. Read synchronization remains opt-in and
notifications start disabled. Drafts remain in memory only.

## Earlier releases

See the [GitHub releases](https://github.com/coldi1337/DankChat/releases) for
0.1.0 through 0.4.0.
