# eww-journals

Basic interactive light journal/notification system for tracking work. Currently tracks status of
journals (recency of last update), and active threads list.

## The journal format

Each project gets one markdown file in `~/journals/`. Stop notes get appended
to the top of the `## Stop notes` section as you work. See
[`templates/project-journal-template.md`](templates/project-journal-template.md)
for the format.

Each stop note has four slots:

- **State** — current state of the work in one sentence
- **Just did** — concrete things you did this session
- **Next** — specific enough to start without thinking
- **Threads** — open questions, blockers, decisions pending

## Requirements

- A Wayland desktop environment with `wlr-layer-shell` support (tested on
  Pop!_OS with COSMIC)
- [eww](https://github.com/elkowar/eww) built with the `wayland` feature
- `cosmic-randr` (or adapt `launch.sh` for your compositor's monitor detection)
- `python3`
- `xdg-open` and a markdown handler registered in your MIME defaults

## Installation

`install.sh` will:

- Copy configs into `~/.config/eww/`
- Install the systemd user service
- Create `~/journals/` if it doesn't exist
- Enable the service to start at login

After install, log out and back in, or run `systemctl --user start eww-journals.service`
manually to start it.

## Customization

**Different editor on click.** The click handler uses `xdg-open`, which honors
your system default for markdown. To change which editor opens, set a different
MIME default:

```bash
xdg-mime default code.desktop text/markdown
```

**Different monitor detection.** If you're not on COSMIC, replace the
`cosmic-randr` call in `eww/scripts/launch.sh` with your compositor's
equivalent (`wlr-randr`, `swaymsg -t get_outputs`, etc.).

**Different bucket boundaries.** Edit `BUCKETS` logic in
`eww/scripts/scan_active.py` to change the day thresholds for today / this
week / this month / older.

**Different panel positions.** Adjust the `:anchor` and `:x`/`:y` properties
in `eww/eww.yuck` for each window definition.

## Project structure

```text
eww-journals/
├── README.md                          # this file
├── install.sh                         # one-shot installer
├── eww/
│   ├── eww.yuck                       # widget definitions
│   ├── eww.scss                       # styling
│   └── scripts/
│       ├── scan_journals.sh           # journal list scanner
│       ├── scan_active.py             # active threads parser
│       └── launch.sh                  # window opener
├── systemd/
│   └── eww-journals.service           # user service template
└── templates/
    └── project-journal-template.md    # starting template for new journals
```

## Design choices

A few decisions that shape how the system behaves:

**Threads are local to each stop note.** When you write a new stop note,
you re-list any threads that are still open. Threads that don't carry forward
are implicitly resolved. This gives each entry a self-contained snapshot of
project state at that time, which is valuable history.

**Buckets reflect project momentum, not thread freshness.** A project last
touched today puts its threads in "TODAY" — those threads might be ancient,
but the project is moving. Threads in "OLDER" come from projects that have
stalled, even if the threads themselves were recently written.

**No automatic active list curation.** The active panel shows what each
project's most recent entry declared as open. Automatic tracking of threads
requires heuristics and automated systems that defeat the purpose of journaling the current context.

## Future ideas

Things that have been considered but deliberately left out:

- **Audit dashboard / thread history view.** A separate panel or script that
  walks all entries and surfaces dropped threads. Useful if you find yourself
  losing threads accidentally, otherwise overhead.
- **Click-to-resolve threads.** Would require structured thread IDs to handle
  re-listing properly. Worth building only if hand-curation becomes a
  bottleneck.
- **Resolve/drop prefixes for explicit thread closure.** The parser already
  supports `[resolved YYYY-MM-DD]` and `[dropped]` prefixes; add them to
  threads in your journals to opt into explicit closure tracking.
- **Monitor-aware active columns.** The active panel currently uses one layout
  across all monitors, which can overlap other panels on narrow or portrait
  displays. A future version could read each monitor's width from `cosmic-randr`
  and generate per-monitor active layouts with fewer columns on narrow screens.

## License

Whatever you like. This is personal tooling, not a product.
