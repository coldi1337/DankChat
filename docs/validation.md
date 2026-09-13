# Validation record

Development environment: Arch Linux, DMS 1.6.1, Hyprland 0.56.2, Python 3.14.

## Automated

- 23 DankChat tests pass: account/provider identity separation, literal text,
  normalization, notification counts, disabled providers, recipient validation,
  no automatic retry, disconnect lifecycle, message bounds, read-receipt
  separation, a real stdio subprocess using temporary private directories,
  QR expiry/recreation, password-required handling, QR cleanup, chronological
  message ordering, Telegram chat timestamps, and pinned chat normalization.
- 151 retained upstream backend/asset tests pass.
- One upstream test is skipped: it inspects Omarchy's installer and release
  scripts, which DankChat does not ship.
- DMS plugin manifest schema passes.
- All six QML components parse with the installed qmlformat.
- Five Qt link-rendering tests pass (seven including setup/cleanup), covering
  escaping, query parameters, punctuation, newlines and allowed URL schemes.

## Live DMS checks

- Plugin discovered and loaded as `dankChat`, with one daemon.
- Added widget to existing horizontal bar without removing existing widgets.
- Demo dropdown opens from the widget.
- App opens independently; it uses a normal resizable window. A narrow
  Hyprland window-rule exception avoids the general DMS floating-window rule.
  Live compositor inspection reports `floating: false`, `fullscreen: 0`.
- Visually inspected the shared chat list, messages and composer using demo data.
- Settings persist across a DMS restart.
- Demo mode disconnects the bridge. Leaving demo mode starts one bridge and
  processes unauthenticated status requests without pending work remaining.
- Fresh plugin runtime logs have no reported DankChat reference/type errors.
- Both providers now report authenticated status. User reported WhatsApp history
  syncing and a successful Telegram login after correcting QR expiry.
- Follow-up fixes address long chat names/previews, unread badge width,
  vertically centered composer text, themed text context menus, and a bounded
  password-field layout that disappears after authentication.

## Pending before submission

- Completed WhatsApp history synchronization and both chat workflows still need
  confirmation after the latest UI corrections.
- User-initiated text/reply/attachment acceptance tests; no agent test sends.
- Live unread updates, reconnect, suspend, and enable/disable of an authenticated
  account, including synchronization cleanup.
- Shared draft behavior exercised through actual UI input, narrow window,
  vertical bar and multi-monitor interactions.
- Live pin/unpin synchronization, inline media/download/playback and link clicks.
- Nonmodal dropdown focus and click-through behavior on the compositor.
- Fresh-checkout installation and README command verification.
- Representative synthetic-only preview; no existing desktop screenshots are
  approved for publication.
- Public repository/registry validators and maintainer review.

## Isolated regression tests (2026-09-13)

`python3 scripts/test-ui` uses copied DMS components, a separate Quickshell
process, private XDG directories, a private session bus and synthetic data.
It opens and closes the non-native attachment picker twice, changes account
states and tests 360/480/760/1080 logical-pixel layouts. All ten stock palettes
are tested in light/dark mode, with a minimum 4.5:1 outgoing-bubble text contrast.
German narrow-account and wide-chat renders were visually inspected. Font sizes
were also exercised at 150% with long sender names.

`python3 scripts/test-ui --service` runs the actual Service.qml with a fake
JSON-lines backend: 240 chats, 80-message histories, 200 refresh/selection and
surface-switch steps. It does not connect to any real provider or send messages.

The original attachment crash stack entered GTK/GVFS. The picker now sets
DontUseNativeDialog. Additional live QML crashes were not reproduced in the
isolated runs; this is not evidence of stability on every compositor or Qt build.
DankChat was temporarily disabled in the real bar while investigating.

New account tests verify Telegram logout failure preserves state, successful
logout cleanup, WhatsApp QR rotation, event filtering and cancellation. Receipt
tests check signatures, account/chat separation, monotonic state and absence of
fabricated historical/incoming-message confirmations. Real logout/relink and
receipt acceptance still require user action; existing sessions were not revoked.

After the isolated checks passed, DankChat was reloaded into DMS and re-enabled.
The bridge reported both existing sessions authorized, with no pending requests.
No real messages were sent and no account was logged out during validation.
