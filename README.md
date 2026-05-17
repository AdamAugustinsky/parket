# parket

minimal tiling window manager for macOS. emulates workspaces by moving windows offscreen - no private API, no SIP modifications. inspired by [dwm](https://dwm.suckless.org/) and [AeroSpace](https://github.com/nikitabobko/AeroSpace).

swift, zero dependencies.

## features

- **workspaces** - 9 virtual workspaces via offscreen window hiding
- **master-stack tiling** - new windows auto-tile in dwm-style layout
- **monocle layout** - per-workspace fullscreen mode, toggle with option+m
- **tabbed pane groups** - group related windows into one layout slot and switch them as native tabs
- **spatial navigation** - jump from any stack window straight back to master with option+h
- **window gaps** - small configurable inner gaps between tiled windows
- **menubar indicator** - badge widgets show active workspace and occupied ones
- **custom keybindings** - bind any key combo to shell commands via toml config
- **multi-monitor** - per-display workspaces, each monitor has its own workspace set
- **crash safety** - all windows restore on exit

## this fork adds

- First-class tabbed pane groups, so one tiled slot can contain multiple related windows.
- Native AppKit tab strip UI using `NSSegmentedControl`, `NSGlassEffectView` on macOS 26+, and `NSVisualEffectView` fallback on older macOS.
- Stable pane identity with `PaneID` and active-window state, avoiding tab/index drift after grouping, focusing, or app switching.
- Manual grouping commands for moving the focused window into the previous or next pane.
- Manual expel commands for splitting the active tab out before or after its grouped pane.
- Group-aware movement, workspace moves, monitor moves, app reveal, window removal, and restore behavior.
- Spatial master-stack focus: `Option+H` jumps from any stack pane to master, and `Option+L` returns to the remembered stack pane.
- Linear vertical stack focus with `Option+J/K`.
- Configurable inner window gaps with `window_gap`.
- Comma-separated keybinding aliases and explicit `control+`, `option+`, `command+`, and `shift+` modifier parsing.
- Adam-focused default config with nine named lanes, Ghostty launcher, Raycast binding, and Mission Control binding.
- Re-adoption of focused tileable windows after app activation/fullscreen transitions when macOS does not emit a new-window event.
- Expanded pane and tiler tests covering tab grouping, expel, non-wrapping moves, spatial focus, tab identity, and window gaps.

## keybindings

| key | action |
|-----|--------|
| `Option + 1-9` | switch workspace |
| `Option + Shift + 1-9` | move focused window to workspace |
| `Option + H/L` | focus left/right across the master split |
| `Option + J/K` | focus next/previous window in the stack order |
| `Option + Shift + H/J/K/L` | reorder focused tab or pane |
| `Option + Return` | toggle monocle layout |
| `Option + Shift + Return` | swap focused pane/group with master |
| `Option + Tab` | switch to last active workspace |
| `Option + Control + H/L` | group focused window into prev/next pane |
| `Option + Control + Shift + H/L` | expel active tab before/after grouped pane |
| `Option + ,` / `Option + .` | focus prev/next monitor |
| `Option + Shift + ,` / `Option + Shift + .` | move window to prev/next monitor |

all keybindings are configurable - see configuration below.

## configuration

edit `~/.config/parket/config.toml`. all fields are optional - defaults are used for anything not specified.

```toml
workspace_count = 9
master_ratio = 0.55
window_gap = 6
modifier = "option"    # "option", "control", or "command"

[bindings]
focus_left = "h"
focus_right = "l"
focus_next = "j"
focus_prev = "k,control+tab"
move_next = "shift+j,shift+l"
move_prev = "shift+h,shift+k"
swap_master = "shift+return"
toggle_layout = "return,shift+f,control+f,slash"
focus_monitor_prev = "comma"
focus_monitor_next = "period"
move_monitor_prev = "shift+comma"
move_monitor_next = "shift+period"
last_workspace = "tab"
group_prev = "control+h"
group_next = "control+l"
expel_prev = "control+shift+h"
expel_next = "control+shift+l"
decrease_master_ratio = "minus"
increase_master_ratio = "equal"
reset_master_ratio = "shift+b"

[[custom]]
key = "grave"
command = "open -na Ghostty"

[[custom]]
key = "control+space"
command = "open -a Raycast"
```

custom bindings always include the modifier key (option by default). prefix with `shift+` to add shift to the combo.

to reload config at runtime, use the "Reload Config" option in the menubar menu.

## requirements

- macOS 14+, Apple Silicon
- accessibility permission
- input monitoring permission

## install

```bash
brew tap basuev/parket
brew install --cask parket
```

or build from source:

```bash
make install
open /Applications/parket.app
```

grant permissions in system settings -> privacy & security when prompted, then relaunch.

## update

```bash
brew upgrade --cask parket
```

or from source:

```bash
make install
```

replaces only the binary - permissions persist.

## uninstall

```bash
brew uninstall --cask parket
```

or:

```bash
make uninstall
```

## comparison

|  | parket | [AeroSpace](https://github.com/nikitabobko/AeroSpace) | [yabai](https://github.com/koekeishiya/yabai) | [Amethyst](https://github.com/ianyh/Amethyst) |
|--|--------|-----------|-------|----------|
| language | swift | swift | c / obj-c | swift |
| dependencies | 0 | 4 | 1 (skhd) | 1+ |
| private API | no | yes (1) | yes (many) | no |
| SIP disabled | no | no | optional | no |
| auto-tiling | yes | yes | yes | yes |
| virtual workspaces | yes | yes | yes | yes |
| config | toml | toml | cli | gui + yaml |
| layouts | master-stack, monocle | tree (i3) | bsp | 14+ |
| lines of code | ~1k | ~15k | ~20k | ~15k |

parket is not trying to compete with these projects. it exists for those who want the absolute minimum: a single layout, a few keybindings, zero dependencies, and code small enough to read in one sitting.

## resource usage

parket is designed to stay out of your way. here is how it compares to AeroSpace under identical conditions (Apple Silicon, macOS 26, 6 tiled windows, continuous open/close workload):

- **2x less memory** - 41 MB vs 83 MB
- **near-zero CPU** - 0.0% even during active window management, vs 2% for AeroSpace
- **40x fewer context switches** - less work for the kernel, less energy spent

fewer threads, fewer wakeups, longer battery life. you won't find parket in Activity Monitor unless you go looking for it.

<sub>measured with `scripts/benchmark.sh`. run it yourself - numbers are reproducible.</sub>

## license

MIT
