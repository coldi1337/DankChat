# Validation record

## Current acceptance status

On 2026-09-13, the maintainer reported completing broader hands-on testing and
confirmed that the current features work without issues in their setup. On that
basis, registry PR #884 is ready for review; the earlier draft hold is lifted.
This is maintainer-reported acceptance, separate from the automated results below.
No additional compositor/distribution coverage or individual test cases are
inferred from that report. Earlier crash reports and draft gates below are retained
as development history and do not describe the current submission status.


Development environment: Arch Linux, DMS 1.6.1, Hyprland 0.56.2, Python 3.14.

## Automated

- 26 DankChat tests pass: account/provider identity separation, literal text,
  normalization, notification counts, disabled providers, recipient validation,
  no automatic retry, disconnect lifecycle, message bounds, read-receipt
  separation, a real stdio subprocess using temporary private directories,
  QR expiry/recreation, password-required handling, QR cleanup, chronological
  message ordering, Telegram chat timestamps, and pinned chat normalization.
- 152 retained upstream backend/asset tests pass.
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

Follow-up: the standard Qt picker was replaced by DMS FileBrowserContent inside
a themed popup. Isolated UI coverage includes attachment selection and save-mode
opening/cancellation. The fake backend exercises automatic media loading and
rejects duplicate downloads; export tests verify exact provider/message lookup,
private atomic copies, overwrite behavior and invalid destinations.

Reply navigation preserves provider reply IDs and loads bounded context for older
messages. A backend regression covers messages outside the latest page, timestamp
ties and rejection of IDs belonging to another chat. Search misses now have a
separate empty state from unlinked accounts.

Current status: a subsequent live reload crashed the whole DMS process again
(SIGSEGV in Qt QML property lookup/binding evaluation, 2026-09-13 04:51 CEST).
DankChat is disabled again; the bar is running. The earlier GTK/GVFS crash and
this QML stack are distinct observations. Clearing the QML disk cache did not
establish a fix. No further live-shell reload tests are authorized by our current
testing plan. Isolated service recreation passes but does not reproduce the
actual-host failure. Release and registry submission remain blocked on stability.

The themed emoji picker uses an in-scene Popup.Item. Isolated UI checks exercise
opening it during narrow/wide layout changes, selection replacement (including
variation-selector emoji), insertion at the cursor with UTF-16 cursor advancement,
and rejecting insertion after switching chats. These tests use synthetic drafts
and never send messages. The picker contains a curated set of common emoji;
emoji search and skin-tone selection are not implemented.

The user subsequently requested re-enabling DankChat to reproduce the crash;
both account bridges and the bar were running after activation. Emoji rendering
was then corrected: default ItemDelegate padding left too little text space in
40-pixel cells, hiding the emoji despite a populated model. Explicit zero padding
and unelided single-line labels restore the grid. An isolated regression now checks
actual delegate text space, and its synthetic popup render was visually inspected.

Chat opening now retains the request to scroll to the latest message across the
empty/loading state and deferred ListView layout. Content-height changes keep the
view at the end while following new messages. Wheel/drag scrolling and quoted
message navigation stop following. Isolated UI regressions cover delayed 80-message
loads, chat switching, reopening the same chat, late content growth, and preserving
the position while reading older messages during refresh.

The curated emoji subset is superseded by the complete Unicode Emoji 17.0
catalog: 3,953 fully-qualified/component entries, with CLDR 48 English/German
search annotations and retained Unicode licensing. Qt tests verify catalog
uniqueness, Emoji 17 coverage, compound families, skin tones, flags, bilingual
case/accent-insensitive keyword searches, empty results and category filtering.
The isolated UI verifies the actual German search result for Austria, no-result
state, clearing/reopening to the full catalog and delegate rendering. Category
buttons and the full scrolling grid were visually checked using synthetic data.

Explicit “Mark as read” is available in each chat's context menu. Provider-mocked
tests verify Telegram's mark_read command and WhatsApp's server chat_action(read),
including failure propagation and account routing. WhatsApp does not substitute
local notification acknowledgement for this explicit action. The UI suppresses
duplicate requests and only clears the unread count after success. No real chat
was marked read during agent validation; cross-device acceptance remains manual.

The unread-only chat filter composes with provider selection and trimmed local
search; its badge counts matching unread chats, not individual messages. Isolated
service checks use 240 synthetic chats to verify the unread subset, provider/search
intersection, zero results and clearing the toggle. UI checks cover the button at
narrow/wide sizes and stock light/dark themes, including larger German labels.

A last-message video regression uses an ffmpeg-generated synthetic MP4 (ffmpeg
is required for `scripts/test-ui`). Replacing the array-backed view model after a
status update destroyed and recreated the player; the regression failed before
incremental ListModel synchronization and passes afterward. The UI now updates
rows by message ID, preserving unrelated delegates and players. Repeated loading
of the same media URL is also suppressed, and player activation no longer follows
inherited item visibility. Tail scrolling avoids forcing layout from every
content-height notification. The regression checks player identity and stable
bottom scroll after another message changes; existing delayed-load, chat-switch,
manual-scroll and emoji checks remain enabled. Real provider/video acceptance
still requires reproducing the user's specific chat after installation.

The incremental message model uses dynamic roles to preserve message maps across
append/update operations. A fixed-role prototype produced List/VariantMap type
warnings and failed the service stress check; that prototype was not installed
in the live shell. The harness now fails on role-assignment warnings and binding
loops, reports IPC timeouts cleanly, and uses a valid synthetic PNG. Final UI and
200-step service tests both passed, including changes to the video row itself.

## Final automated pass — 2026-09-13

- `bash scripts/test`: 29 own Python tests passed; 153 retained WhatsApp tests
  ran (152 passed, one intentionally skipped upstream installer test); link and
  emoji QtTest suites passed (7 and 5 results including setup/cleanup); all six
  QML components parsed; plugin manifest schema passed.
- `python3 scripts/test-ui`: passed the final UI, translation, picker, search,
  scroll and last-message-video regressions. The video retains its player and
  visible position during updates to another row and to its own status.
- `python3 scripts/test-ui --service`: passed the 200-step synthetic service run,
  including recreation, filters, automatic downloads and older-reply context.
- `git diff --check`: clean.

Telegram's PINNED_DIALOGS_TOO_MUCH now produces an actionable localized message:
5 pinned chats in the main list without Premium, 10 with Premium; unpin another
chat first. Only this RPC exception is mapped to the limit explanation; network
errors still propagate, and unpinning remains possible. The error class was also
verified against the installed Telethon dependency. Sources:
https://core.telegram.org/method/messages.toggleDialogPin and
https://telegram.org/faq_premium.

The final checks also corrected the DMS translation table shape for newer labels
and a remaining empty-caption layout bug: Qt RichText returns an HTML document
for an empty TextArea, so visibility must use the original message text. Stored
row signatures avoid updating identical message maps just because Qt enumerates
their keys in a different order. The video test measures visible position rather
than absolute contentY, which can change with ListView origin estimates.

These are automated and isolated results. No agent test sent real messages,
marked real chats read, changed real pins, or logged out either account. Earlier
whole-shell crashes remain a release qualification concern; this pass does not
prove they cannot recur. The repository has not been submitted to the registry.

## Registry preparation — 2026-09-13

A synthetic-only preview was rendered from `tests/preview_shell.qml` using
`python3 scripts/test-ui --preview`, visually inspected, and saved as
`docs/preview.png`. No live account content or desktop pixels are included.
Installer tests now cover a fresh checkout and an existing registry installation
path with private config/data directories and stub DMS/systemd commands. Both
are idempotent; the registry path does not create a duplicate plugin symlink.
The project Python suite now contains 31 passing tests. The registry entry is
limited to the tested Arch/Hyprland combination and does not claim central i18n
approval. Submission is a draft while the documented stability/acceptance work
remains open.

Registry draft submitted: https://github.com/AvengeMedia/dms-plugin-registry/pull/884.
DankChat's repository is now public. The registry schema validator and changed-entry
link/manifest validator both passed against the public repository and preview URL.
This records submission, not maintainer approval or catalog availability.


## Clipboard attachments and reply preview — 2026-09-14

- 45 project Python tests and 152 retained WhatsApp tests passed (one intentional installer skip), plus QtTest suites, QML parsing and manifest validation.
- Clipboard tests use mocked image/file-list content, check private staging and cleanup, reject remote URLs, and preserve normal text paste. They do not read or replace the user's clipboard.
- Isolated QML tests cover a long quoted reply in narrow windows, multiple attachment selection/deduplication and clipboard image staging with a synthetic PNG.
- The 200-step service run covers sequential three-file sending and stopping after a simulated failure on the second file. Automatic media loading no longer clears an existing send error.
- The promotional README image is rendered from the real QML interface with synthetic chats, using the requested Bitwarden preview layout as a visual reference.
- No real files/messages were sent to Telegram or WhatsApp during automated testing. Native album sending is not implemented; attachments are sent sequentially.


## WhatsApp attachment availability — 2026-09-14

A local download failure was reproduced for an indexed image with neither a download path nor a media key. The provider returned a missing-metadata error, which the bridge previously converted to its generic warning about resending. Message fetching and normalization succeeded.

The adapter now exposes download availability without exporting media keys or download URLs. The UI keeps unavailable attachments visible, skips their automatic downloads and distinguishes media failures from send failures. A later metadata update can make the attachment downloadable again.

47 project Python tests and 152 retained WhatsApp tests passed (one intentional skip), plus QtTest and QML/schema checks. The synthetic service fixture now includes an attachment without metadata and fails if automatic loading tries to download it.


## Incoming activity and voice player — 2026-09-14

Telegram uses incoming UserUpdate events and server-returned user status, preserving coarse/hidden last-seen privacy. WhatsApp wacli 0.17.1 exposes signed chat_presence webhooks (composing/paused, including audio recording); its interface does not expose online/last-seen events. Activity expires after eight seconds without renewal and is never inferred from chat/message timestamps. The existing receipt interpretation and checkmark colors remain unchanged.

The voice player adds seeking, elapsed/total time, and 1×/1.5×/2× speed. UI fixtures use a silent three-second Opus file to exercise duration, speed, seeking and pausing when chat surfaces close. Presence tests cover signature verification, per-chat/per-sender isolation, pause events, expiry, Telegram privacy statuses and cached server lookups. Live incoming events depend on what each provider sends; no outgoing activity or real test messages were sent.


## Voice recording — 2026-09-14

The microphone button starts a private FFmpeg/PulseAudio capture (also supported by pipewire-pulse), encoding mono OGG/Opus. The UI offers stop, playback preview, discard and explicit send. FFprobe validates the finished file and provides duration for Telegram's voice-note attribute. WhatsApp uses the existing validated voice-draft sender. No text caption is consumed. A five-minute cap and close/chat-switch/reload cleanup bound recording lifetime.

Tests use a synthetic silent FFmpeg input, never the live microphone: actual encoder output, private permissions, duration, unavailable input, draft ownership, failure retention, confirmed-send cleanup and provider-specific voice routing. English/German UI fixtures cover the microphone control and preview; the 210-step service fixture covers start/stop/send, preserved text and stopping when surfaces close. All 55 project tests and 152 retained WhatsApp tests pass (one intentional skip), alongside QML/QtTest/schema checks. Real microphone quality and delivery to WhatsApp/Telegram await the user's hands-on test before publication.


## Message deletion — 2026-09-14

Single-message deletion is exposed through the text context menu and a delete icon (including media-only messages), followed by a translated confirmation. WhatsApp offers deletion for yourself and, for outgoing messages, everyone. Telegram hides self-only deletion for Channel entities (supergroups/channels), and the backend independently rejects that scope because Telethon otherwise deletes for everyone regardless of the revoke flag. Telegram also fetches the message and verifies its chat ID before deletion; the API itself does not guarantee private-chat ID membership. There is no fallback to a different deletion scope.

59 project tests and 152 retained WhatsApp tests pass, plus QML/QtTest/schema checks. English/German UI fixtures verify confirmation, scope defaults, incoming WhatsApp restrictions, Telegram group scope and cancellation on chat switch. The service fixture checks successful removal/reply cleanup, rejection of stale chat selection and retention on failure. All deletion calls are synthetic; no real conversations were modified. A transient voice-preview layout timing failure in one UI run was followed by a passing rerun; the fixture now waits a bounded two seconds for the loaded preview/layout instead of assuming immediate readiness.


## v0.4.0 acceptance — 2026-09-14

The maintainer reports that the current features appear to work in their setup and has approved committing, pushing and releasing this version. This is user-reported hands-on acceptance; automated tests continue to use synthetic messages and microphone input. The release includes voice recording/playback controls, incoming activity, message deletion, the missing WhatsApp media metadata fix, translations and the shorter documentation.


## Clipboard and synchronization — 2026-09-20

Synthetic regression tests cover image-data fallback when a clipboard URI is
unusable, image decoding/conversion, concurrent clipboard/presence/chat requests
during a blocked download, and logout waiting for transfers. Telegram subscribes
to incoming and outgoing read events; WhatsApp unread counts use the service's
unread state together with local notification acknowledgements.

All 66 project tests and 152 retained WhatsApp tests pass (one intentional skip),
as do QtTest, QML parsing and manifest validation. The 246-step isolated service
fixture checks external read updates, temporary-error retention, attachment drafts
across chat switches, bridge restart and text-draft retention. UI fixtures cover
clipboard staging and the voice-preview layout. No real messages were sent or
marked read by the tests. Real clipboard sources and cross-device timing still
need hands-on verification.

Both German and English isolated UI runs pass. During live plugin reload,
Quickshell crashed in Qt QML (`QV4::Value::sameValueZero`). Starting `dms.service`
restored the bar; DankChat then reported both accounts authorized, the bridge
running and no pending requests, and WhatsApp sync was active. This reload crash
is unresolved; the passing isolated reload fixture does not establish that live
hot reload is safe.


## Unread-badge regression — 2026-09-20

The raw WhatsApp unread count bypassed the existing local acknowledgment made
on chat opening. Restored the local badge behavior, capped by the remote unread
count so a remote read clears it even if a notification snapshot is stale.
Regression tests cover opening/dismissal, a subsequent new message, remote read,
and helpers without notification metadata. Successful acknowledgments request
a chat-list refresh. This does not enable automatic WhatsApp read receipts.

## Performance and compatibility — 2026-09-26

The UI retains up to 12 recent chat message lists, revalidates without blanking
cached content, and isolates responses by chat/request. Confirmed attachment
results are shown per file, with bounded private preview copies; stale history
responses do not immediately remove a confirmed send. Visible media is scheduled
first with two Telegram download slots and one WhatsApp slot. Sends, chat-list
refreshes, presence and message reads have separate bounded lanes. WhatsApp's
underlying store can still serialize network operations. Its open chat is checked
every 1.5 seconds. Unchanged chat lists no longer replace the QML model.

Telegram's duplicate eager media/avatar fetches are disabled in the DankChat
adapter (cached avatars remain available). Message formatting reuses entities
from dialogs/message responses. Explicit downloads use private staging and an
atomic rename; cancellation leaves no partially published image. Preview decode
size is capped at 960 pixels per axis, while opening the gallery uses the original.

Chat switches cancel the previous flick and settle at the latest message again
after layout and late media-size changes. Intentional scrolling up is preserved.
The 121-step UI fixture exercises a late image and background receipt update.
The 262-step service fixture additionally checks instant cached navigation,
out-of-order chat responses, confirmed-send reconciliation and preserved receipts.

GitHub issue #2: replaced the exact wacli 0.17.1 check with a version floor plus
required-command/flag probes. Both the installed 0.17.1 and official 0.19.0 binary
passed; the actual 0.19.0 SQLite schema passed the chat adapter smoke test using a
disposable store. The release archive SHA256 matched its published checksums.

GitHub issue #1: the reported DMS Git commit 80060ee925ffcea6f5e759cbf79393a2f6e05f2d
no longer exports DankPopoutStandalone. DankChat now uses the public DankPopout
wrapper. The service fixture passed against both local DMS 1.6.2 and that exact
source commit with its pinned dank-qml-common submodule
928cc746e57e4e2a06a5ee40fe137e425fcd8cfe. No ChaoticAUR package was installed.
This verifies those QML sources on the installed Qt/Quickshell runtime, not every
aspect of the reporter's package or machine.

76 project tests and 152 WhatsApp tests pass (one intentional skip), plus QtTest,
QML parsing and manifest validation. German/English UI and service fixtures pass.
Tests used synthetic messages; no real sends or read mutations were performed.

After stopping DMS/sync, the local WhatsApp store and old executable were backed
up privately under $XDG_STATE_HOME/dankchat/backups/before-wacli-0.19.0-2xnbaw51.
wacli 0.19.0 was installed, then DMS was started normally. Both providers report
authorized, the bridge and sync service are running, and live viewStatus reports
no QML/media component errors. The previous live-hot-reload crash remains unproven
resolved; a normal restart was used. User acceptance of real transfers/scrolling
is still pending. No commit, push, release or issue comment was made in this pass.

## 2026-09-26 — accounts, settings, search and read synchronization

The local development build now has independently named Telegram/WhatsApp accounts,
account tabs, app settings, message search/media browsing, editing, notification
policies, cache management, update checks, diagnostics export and keyboard shortcuts.
Search/gallery actions are icons in the chat header. Persistent drafts were explicitly
excluded. All new application-owned UI/error strings have German translations with
English source fallback.

89 project tests pass. 152 vendor WhatsApp tests pass with one intentional skip;
QtTest, QML parsing and manifest validation pass. German and English UI fixtures
cover the new settings/account/search views at narrow widths and enlarged font sizes.
The 290-step service fixture passes on current DMS 1.6.2 and the issue #1 Git source
80060ee with its pinned DankCommon module. The harness explicitly checks that the
actual chat view loaded. No alternative DMS package was installed.

New coverage includes identical chat IDs under different accounts, independent
transfer lanes, safe account identities/legacy paths, tab rename/filtering, search
pagination and result navigation, edit ownership, protected cache cleanup, completed
read-only download caching, actionable CDN rejection errors, GitHub release caching,
notification markup escaping and bounded Telegram read acknowledgements. Fixture
messages and account databases are synthetic; tests never send to real contacts.

Live activation used a regular DMS restart. The additional-account systemd template
was installed, both existing accounts remained authorized, DMS and WhatsApp sync
were active, and viewStatus reported a loaded UI with no component errors. The log
check found no DankChat QML reference/type/binding errors since restart. Both services'
read-sync preferences were enabled at the user's explicit request. GitHub's latest
release remains v0.4.0; the installed source is correctly identified as locally modified.

Actual linking of a second account, real message editing/uploads and phone-side
read synchronization still need user acceptance. WhatsApp mentions-only notifications
are unavailable because wacli lacks reliable mention metadata; the UI documents that
policy as silent for WhatsApp. No commit, push, release or registry submission was made.


Account selectors were subsequently changed at the user's request from a
horizontal scrolling strip to vertically stacked full-width buttons. Long account
labels are elided while retaining the service suffix and full-name tooltip.
German/English isolated UI fixtures pass with the added sidebar screenshot
(137 steps). The local layout was activated with a second normal DMS restart.


## 2026-09-26 — 0.5.0 release validation

93 project tests pass, including installer checksum rejection, archive symlink
rejection, atomic replacement and previous-binary preservation. 152 vendor tests
pass with one intentional skip; Qt link/emoji tests, QML parsing and manifest
validation pass. The official wacli 0.19.0 command surface and disposable database
adapter pass. Static application UI strings have German translations.

A fresh isolated installation downloaded the official wacli release, checked its
SHA-256, created a real Python environment and installed all Python dependencies.
A second setup run kept the compatible executable and succeeded again. Plugin
symlink, launcher, default sync unit and account template were verified. Only DMS
scan and systemd reload were stubbed; no live account files were used.

One German UI run crashed inside Qt's QML garbage collection during the fixture's
recursive child-list traversal. The fixture now searches iteratively using indexed
child access. Subsequent UI runs pass, including explicit full-width account/unread
button checks. This does not establish that every possible Quickshell runtime crash
is resolved. The real live bar was unaffected by the isolated test failure.

The README preview is rendered from the current QML with English synthetic chats,
named accounts and the default purple theme. No private conversations are included.
The previous live-interaction limits (new real account linking, phone-side reads and
real transfers) still apply; automated tests use synthetic providers.
