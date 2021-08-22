# Multi-Monitor-Quad-Tiling (MMQTiling)

Move windows between monitors and tile them usind a quad grid. The tiling actions are relative to the current position, e.g., when the window is on the left half of the screen spanning over the full height and you invoke a tile-top command, the window will then be on the top left quarter of the screen. Moving windows between monitors will not change the quarter/half/full tiling of the window. If you have differently sized monitors the window size will be changed accordingly. Movement between monitors is equally relative, e.g., invoking a move-left will search for the next screen that is to the left of the current screen.

## Usage

```
Usage: ./mmqtiling.sh left/right/top/bottom [use_tiling]
```
* `use_tiling` - if present, the window is tiled in the given direction, else it is moved

In Xfce4 you can use the `Settings Manager > Keyboard > Application Shortcuts` to set keyboard shortcuts for the script (how it is intended to be used). I use:
| Command | Shortcut |
|---------|----------|
| `/path/to/mmqtiling.sh bottom` | `Ctrl+Super+Down` |
| `/path/to/mmqtiling.sh bottom use_tiling` | `Shift+Ctrl+Super+Down` |
| `/path/to/mmqtiling.sh left` | `Ctrl+Super+Left` |
| `/path/to/mmqtiling.sh left use_tiling` | `Shift+Ctrl+Super+Left` |
| `/path/to/mmqtiling.sh right` | `Ctrl+Super+Right` |
| `/path/to/mmqtiling.sh right use_tiling` | `Shift+Ctrl+Super+Right` |
| `/path/to/mmqtiling.sh top` | `Ctrl+Super+Up` |
| `/path/to/mmqtiling.sh top use_tiling` | `Shift+Ctrl+Super+Up` |

## Dependencies

You need to install: bash, xdotool, wmctrl

## Known bugs

When rapidly calling the script (i.e., parallel execution of it), it might behave weird, because there are no mechanisms protecting the script from interfering with another instance of itself.

## Code of Conduct

[We have one](code_of_conduct.md), and you're expected to follow it.

## Thanks

* [icyrock](http://icyrock.com/blog/2012/05/xubuntu-moving-windows-between-monitors/) post for initial development
* [@jordansissel](https://github.com/jordansissel) for his excellent [xdotool](https://github.com/jordansissel/xdotool)
* [jc00ke](https://github.com/jc00ke/move-to-next-monitor) upstream repo
