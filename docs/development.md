# Development

The development environment is Arch Linux, Hyprland 0.56.2, DMS 1.6.1,
Quickshell 0.3.1 and Qt 6.11.2. See the [validation record](validation.md) for
coverage and results; other compositor/distribution combinations aren't verified.

## Tests

After running `sh scripts/setup-telegram`:

```sh
.venv/bin/pip install jsonschema
sh scripts/test
```

This runs Python tests, QtTest suites, QML parsing and manifest-schema validation.
Qt test tools must be installed.

The UI harness needs a working DMS/Wayland session, FFmpeg, `qs` and
`dbus-run-session`. Set `DANKCHAT_DMS_SOURCE` to your active DMS source directory
if it differs from the default in `scripts/test-ui`.

```sh
python3 scripts/test-ui
python3 scripts/test-ui --english
python3 scripts/test-ui --service
```

These checks open temporary windows with synthetic chats, generated media and
isolated account directories. They don't send messages or use your account databases.

## Preview and emoji data

Render the promotional screenshot using sample conversations:

```sh
DANKCHAT_PROMO=1 python3 scripts/test-ui --preview
```

Regenerate the pinned Unicode/CLDR emoji data with
`python3 scripts/update-emoji-data`. Generation requires network access;
the picker itself works offline.


## Compatibility checks

`python3 scripts/check-environment` checks the DMS window and file-picker component
files without changing the session. It recognizes both legacy and modern file
browsers, including their DankCommon dependency. This is a file preflight, not a
QML runtime test. `python3 scripts/test-wacli /path/to/wacli` checks the command interface
and chat adapter against a disposable database. It does not use linked accounts
or send messages. The recommended, tested wacli release is 0.19.0; compatible
versions from 0.17.1 are accepted.

The UI runner discovers the local DMS source directory automatically. To test a
different DMS revision without installing its package, download/check out its
source including its pinned `dank-qml-common` submodule, then run:

```sh
DANKCHAT_DMS_SOURCE=/path/to/DankMaterialShell/quickshell python3 scripts/test-ui --service
```

This uses the chosen QML source with the installed Qt/Quickshell runtime in an
isolated session. It does not reproduce every difference in a distributor's
package or runtime.


## Accounts and application features

`backend/accounts.py` retains the two legacy empty account IDs and generates
immutable UUIDs for additional sessions. Labels are editable and never form part
of a path or recipient selector. Bridge validation rejects account/chat mismatch;
control/transfer/download lanes are isolated per account. Telegram helper modules
are loaded independently so session/cache globals cannot cross between accounts.
WhatsApp instances use separate stores and systemd template instances.

`AppSettings.qml`, `AccountView.qml` and `MessageBrowser.qml` hold the new views.
English source strings fall back through DMS I18n; German translations are local.
`backend/library.py` queries Telegram history; the WhatsApp adapter filters local
SQLite rows before pagination. Editing never silently falls back to another action.
`backend/storage.py` manages only explicit media directories, excluding symlinks.
No persistent draft store was added.


## Setup installer

`python3 scripts/setup` checks the installed DMS widget API, prepares the local
Python environment and installs the launcher and systemd units. It downloads the
pinned, tested wacli release only when the expected local binary is missing.
`--update-wacli` explicitly replaces it after SHA-256 and command-interface checks,
keeping the previous binary. The archive is read without extracting paths or links.
`--telegram-only` skips wacli. System packages remain the user's package-manager task.

The fresh-install validation uses an isolated HOME and real release/Python downloads;
only the final DMS scan and systemd reload are stubbed. No accounts are linked.


The attachment dialog loads `FilePickerCompat.qml` lazily. It selects the current
DankCommon `FilePicker` or the legacy `FileBrowserContent` without referring to an
optional type in the chat view. The stable file-browser module import lets
Quickshell register the host modules; the concrete type is then selected lazily
through its module, preserving singleton layout metrics. Selection, save and cancel signals
are mapped to the same application actions; the modern picker supports selecting
multiple attachments at once. A missing picker leaves the conversation usable and
shows a translated error when the dialog is requested.

For picker regression checks, set `DANKCHAT_EXPECT_PICKER=legacy` or `modern` when
running `scripts/test-ui` against the respective DMS source. `--missing-picker`
removes the picker components only from the disposable fixture and must pass;
`--invalid-view` deliberately creates a broken fixture and must exit nonzero with
its original QML error, without a secondary shutdown exception.
