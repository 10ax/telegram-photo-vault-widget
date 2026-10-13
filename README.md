# Telegram Photo Vault

A KDE Plasma 6 system tray widget for the `telegram-photo-vault` service: it
shows whether the service is up, how many files are still queued to upload, what
the worker is doing, how the channel tidy is getting on and how much disk is
left — without opening the web dashboard. It can also start, stop and restart
the service, and ask for a worker run right now.

```
Photo Vault                        Running        [ Dashboard ]
up 1d 5h · starts at boot · 1 restart
[ Stop ]  [ ⟳ ]  [ ● ]
Uploads                                            2 pending
        0 in progress · 0 failed
Worker                                              Running
        started 1d 7h ago · every 15 min
Tidy                                                   Idle
        Last batch 300/300 · captioned 299 · deferred 1
Disk                                    113.4 GB free
        81.03% used · tidy download floor 10 GB
───────────────────────────────────────────────────────────────
Updated 15:02                              Checking in 12s
```

## How it works

The widget shells out to `contents/scripts/telegram-photo-vaultctl`, which
assembles the status from three places and says which one answered:

1. `systemctl --user show telegram-photo-vault.service` — service state, uptime,
   boot behaviour and restart count. This works even while the service is
   stopped, which is the point: the pending count must not vanish just because
   the API is down.
2. `GET http://localhost:8100/api/status` and `/api/system` — worker and tidy
   detail, the upload counts and the disk usage. `"source":"api"`. The
   `X-Api-Key` header is the `API_KEY` from the repository's `.env`, read with
   `grep` and never printed.
3. `sqlite3` in read-only mode on `local-data/telegram_photo_vault.db` — the
   same counts straight from the database when the API cannot be reached.
   `"source":"db"`.

The same helper performs the actions: `start`, `stop`, `restart`, `toggle` and
`run` (`POST /api/run`). The popup shows the helper's output, so a failure says
what went wrong instead of doing nothing.

## Source layout

```
contents/
  config/main.xml             settings entries and their defaults
  config/config.qml           registers the settings page
  ui/main.qml                 applet shell: state, polling, tray icon, actions, popup wiring
  ui/StatusBody.qml           popup body: header, controls, rows, notes, footer
  ui/StatRow.qml              one row: label, right-aligned value, quieter sub-line
  ui/configGeneral.qml        the settings page controls
  js/status.js                pure helpers (counts, durations, state codes)
  scripts/telegram-photo-vaultctl   systemd + API + database status and control
  tests/tst_status.qml        qmltestrunner unit tests for js/status.js
```

There is no icon in the package: the tray uses the theme's
`cloud-upload-symbolic` (`state-warning-symbolic` / `state-offline-symbolic` in
the "swap the icon" mode), so nothing has to be copied into the icon theme.

`dev.sh validate` parses the helper, `metadata.json` and `config/main.xml`, runs
`qmllint` over every QML and JS file, checks that the helper prints a status
object through the database fallback, runs the unit tests, and installs the
package into a throwaway root.

## Requirements

- KDE Plasma 6 (tested on 6.7.5, Wayland)
- `plasma5support` (provides the QML `executable` data source)
- `jq`, `curl`, `systemctl --user`
- `sqlite3` (optional; enables the counts fallback while the service is stopped)
- `telegram-photo-vault` installed as a user service, plus `loginctl
  enable-linger` if it should start without a login

## Install

```sh
./dev.sh doctor      # dependencies, unit, API key, one live probe
./dev.sh status      # the human-readable summary
./dev.sh install     # install for the current user + reload Plasma Shell
```

Then add the widget to the system tray: right click the tray → *Configure System
Tray* → *Entries* → enable **Telegram Photo Vault**.

While editing (Plasma Shell restarts, so the screen flashes briefly):

```sh
./dev.sh upgrade     # apply changes and reload Plasma Shell
./dev.sh windowed    # run the installed widget in a window (no tray needed)
./dev.sh validate    # syntax + lint + unit tests + package checks
./dev.sh test        # just the unit tests for the pure helpers
./dev.sh remove      # uninstall
```

## Settings

Right click the tray icon → *Configure Telegram Photo Vault…*. The **General**
page has:

| Setting | Default | Notes |
|---|---|---|
| Check status every | 30 s | Clamped to 10–3600 s; every check is local (systemd, SQLite, one loopback request) |
| Show the pending count next to the tray icon | off | Scaled to the panel slot and dimmed, since at the default font size the number reads as clutter next to the icon; the count is always in the tooltip and the popup |
| State indicator | Coloured dot | `state-dot` (green running, amber degraded, red attention, grey stopped), `icon-swap` (a different glyph per state, for colour-blind users) or `none` |
| Allow starting, stopping and restarting from the widget | on | Off turns it into a read-only monitor |
| Ask for a second click before stopping | on | Stopping can cut a chunk upload mid-flight; it resumes on the next run |
| Rows: Uploads / Worker / Recovery / Disk | all on | Hidden rows are dropped from the popup and the tooltip |
| Show the last update and the next check | on | Hides the footer row and its separator |

## Behavior notes

- The status check runs every 30 seconds by default. The elapsed and countdown
  labels are recomputed locally each second so they stay live between checks.
- On a failed check the last good values stay on screen and the error is shown
  under the controls.
- **Stopped service**: the service state, the upload counts and the disk usage
  are still shown (systemd, SQLite, `df`); the worker and tidy rows say so
  instead of guessing.
- **Worker stuck?** The widget shows what the worker reports, which is not the
  same as progress: a run that has been going since yesterday reads as
  `Running · started 1d 7h ago`. Compare it with the run interval on the same
  row to judge, and open the dashboard for the journal.
- The tray dot is never the only carrier of the state: the tooltip and the popup
  both say it in words.
- Start/stop goes through `systemctl --user`, so no privileges are needed. The
  unit is not enabled or disabled by the widget — only started and stopped.
