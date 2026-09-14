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
