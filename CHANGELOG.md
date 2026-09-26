# Changelog

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
