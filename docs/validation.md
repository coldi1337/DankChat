# Validation record

Development environment: Arch Linux, DMS 1.6.1, Hyprland 0.56.2, Python 3.14.

## Automated

- 17 DankChat tests pass: account/provider identity separation, literal text,
  normalization, notification counts, disabled providers, recipient validation,
  no automatic retry, disconnect lifecycle, message bounds, read-receipt
  separation, a real stdio subprocess using temporary private directories,
  QR expiry/recreation, password-required handling, QR cleanup, chronological
  message ordering, and Telegram chat timestamps.
- 151 retained upstream backend/asset tests pass.
- One upstream test is skipped: it inspects Omarchy's installer and release
  scripts, which DankChat does not ship.
- DMS plugin manifest schema passes.
- All four QML components parse with the installed qmlformat.

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
- Required feature completion and complete media behavior.
- Fresh-checkout installation and README command verification.
- Representative synthetic-only preview; no existing desktop screenshots are
  approved for publication.
- Public repository/registry validators and maintainer review.
