#!/bin/bash -eu
# Fork of https://github.com/jc00ke/move-to-next-monitor with substantial changes


# used to detect static panels with `wmctrl -l | grep -E $panel_regex` that need to be subtracted from the total usable screen area
panels_regex="xfce4-panel|some-future-panel-regex"


# check dependencies
if ! which xdotool > /dev/null || ! which wmctrl >/dev/null; then
  echo "You need to install: xdotool, wmctrl"
  echo "sudo apt install xdotool wmctrl"
  exit 1
fi

movement_direction="${1:-left}"
hop_only="${2:-hop_only}"
echo "Usage: $0 left/right/top/bottom [use_tiling]"

## TODO validate input


# find geometry and location of active window

window_id=$(xdotool getactivewindow)
window_info=$(xwininfo -id "$window_id")

src_window_abs_left=$(echo "$window_info" | awk '/Absolute upper-left X:/ { print $4 }')
src_window_abs_top=$(echo "$window_info" | awk '/Absolute upper-left Y:/ { print $4 }')
src_window_off_left=$(echo "$window_info" | awk '/Relative upper-left X:/ { print $4 }')
src_window_off_top=$(echo "$window_info" | awk '/Relative upper-left Y:/ { print $4 }')
src_window_abs_left=$((src_window_abs_left - src_window_off_left))
src_window_abs_top=$((src_window_abs_top - src_window_off_top))

src_window_width=$(echo "$window_info" | awk '/Width:/ { print $2 }')
src_window_height=$(echo "$window_info" | awk '/Height:/ { print $2 }')
src_window_width=$((src_window_width + 2*src_window_off_left))  # account for the left and right border
src_window_height=$((src_window_height + src_window_off_top + src_window_off_left))  # account for the window decorations and bottom border

src_window_abs_right=$((src_window_abs_left + src_window_width))
src_window_abs_bottom=$((src_window_abs_top + src_window_height))

src_window_horz_maxed=$(xprop -id "$window_id" _NET_WM_STATE | grep -c '_NET_WM_STATE_MAXIMIZED_HORZ') || true  # bool
src_window_vert_maxed=$(xprop -id "$window_id" _NET_WM_STATE | grep -c '_NET_WM_STATE_MAXIMIZED_VERT') || true  # bool

echo "Current window geometry ${src_window_width}x${src_window_height}+${src_window_abs_left}+${src_window_abs_top} (h=$src_window_horz_maxed,v=$src_window_vert_maxed)"


# find the monitor the active window is on

xrandr_connected_monitors=$(xrandr | grep -i ' connected')
src_monitor_found=0
while read line; do  # loop over monitors (see @done)
  src_monitor_properties=( $(echo "$line" | sed "s/.* \([[:digit:]]\+x[[:digit:]]\++[[:digit:]]\++[[:digit:]]\+\) .*/\1/" | tr 'x' ' ' | tr '+' ' ') )  # we need the regex here because the number of words in the string can vary depending on if the monitor is the primary monitor
  src_monitor_width=${src_monitor_properties[0]}
  src_monitor_height=${src_monitor_properties[1]}
  src_monitor_left=${src_monitor_properties[2]}
  src_monitor_top=${src_monitor_properties[3]}
  src_monitor_right=$((src_monitor_left + src_monitor_width))
  src_monitor_bottom=$((src_monitor_top + src_monitor_height))
  if [[ "$src_window_abs_left" -ge "$src_monitor_left" &&
        "$src_window_abs_right" -le "$src_monitor_right" &&
        "$src_window_abs_top" -ge "$src_monitor_top" &&
        "$src_window_abs_bottom" -le "$src_monitor_bottom" ]]; then
    src_monitor_found=1
    break
  fi
done <<< "$xrandr_connected_monitors"
if [[ "$src_monitor_found" -ne "1" ]]; then
  echo "Couldn't find the monitor the active window is on!"
  exit 1
fi
# correct the available space due to panels
panels=$(wmctrl -lG | grep -E "$panels_regex")
while read line; do  # loop over panels (see @done)
  panel_properties=( $line )
  panel_left=${panel_properties[2]}
  panel_top=${panel_properties[3]}
  panel_width=${panel_properties[4]}
  panel_height=${panel_properties[5]}
  panel_right=$((panel_left + panel_width))
  panel_bottom=$((panel_top + panel_height))
  if [[ "$panel_left" -ge "$src_monitor_left" &&
        "$panel_right" -le "$src_monitor_right" &&
        "$panel_top" -ge "$src_monitor_top" &&
        "$panel_bottom" -le "$src_monitor_bottom" ]]; then
    if [[ "$panel_width" -ge "$panel_height" ]]; then
      echo "Subtracting height of panel \"${panel_properties[7]}\" from source monitor."
      src_monitor_height=$((src_monitor_height - panel_height))
      if [[ "$panel_top" -eq "$src_monitor_top" ]]; then
        src_monitor_top=$((src_monitor_top + panel_height))
      elif [[ "$panel_bottom" -eq "$src_monitor_bottom" ]]; then
        src_monitor_bottom=$((src_monitor_bottom - panel_height))
      else
        echo "Panel is neither on top nor bottom of monitor."
      fi
    else
      echo "Subtracting width of panel \"${panel_properties[7]}\" from source monitor."
      src_monitor_width=$((src_monitor_width - panel_width))
      if [[ "$panel_left" -eq "$src_monitor_left" ]]; then
        src_monitor_left=$((src_monitor_left + panel_width))
      elif [[ "$panel_right" -eq "$src_monitor_right" ]]; then
        src_monitor_right=$((src_monitor_right - panel_width))
        echo "Panel is neither on left nor right of monitor."
      fi
    fi
  fi
done <<< "$panels"
# now we can get the window geometry relative to the current monitor
src_window_rel_left=$((src_window_abs_left - src_monitor_left))
src_window_rel_top=$((src_window_abs_top - src_monitor_top))
src_window_rel_right=$((src_window_rel_left + src_window_width))
src_window_rel_bottom=$((src_window_rel_top + src_window_height))

echo "Geometry of selected source monitor: ${src_monitor_width}x${src_monitor_height}+${src_monitor_left}+${src_monitor_top}"


# find out tiling of the active window on the source monitor

src_monitor_half_width=$((src_monitor_width / 2))
src_monitor_half_height=$((src_monitor_height / 2))

echo "Window position on monitor: ${src_window_width}x${src_window_height}+${src_window_rel_left}+${src_window_rel_top} (center at: $src_monitor_half_width+$src_monitor_half_height)"

vert_slack=$((src_window_height / 4))
horz_slack=$((src_window_width / 8))
if [[ "$src_window_horz_maxed" -eq 1 && "$src_window_vert_maxed" -eq 1 ]]; then
  src_window_tiling_state="maximized"
else
  if [[ "$src_window_rel_top" -ge "$((src_monitor_half_height - vert_slack))"  ]]; then
    src_window_tiling_state_tb="bottom"
  elif [[ "$src_window_rel_bottom" -le "$((src_monitor_half_height + vert_slack))" ]]; then
    src_window_tiling_state_tb="top"
  else
    src_window_tiling_state_tb=""
  fi
  if [[ "$src_window_rel_left" -ge "$((src_monitor_half_width - horz_slack))" ]]; then
    src_window_tiling_state_lr="right"
  elif [[ "$src_window_rel_right" -le "$((src_monitor_half_width + horz_slack))" ]]; then
    src_window_tiling_state_lr="left"
  else
    src_window_tiling_state_lr=""
  fi
  src_window_tiling_state="$src_window_tiling_state_tb$src_window_tiling_state_lr"
  if [[ -z "$src_window_tiling_state" ]]; then
    src_window_tiling_state="floating"
  fi
fi
echo "Current window tiling: $src_window_tiling_state"


# decide on the target window tiling based on the intended movement

if [[ "$hop_only" == "hop_only" ]]; then
  dst_window_tiling_state="$src_window_tiling_state"
  hop_screen="true"
else
  dst_window_tiling_state=""
  hop_screen="false"
  if [[ "$src_window_tiling_state" == "maximized" ]]; then
      dst_window_tiling_state="$movement_direction"
  elif [[ "$src_window_tiling_state" == "floating" ]]; then
    if [[ "$movement_direction" == "left" || "$movement_direction" == "right" ]]; then
      dst_window_tiling_state="floating"
      hop_screen="true"
    else
      dst_window_tiling_state="$movement_direction"
    fi
  else  # tiling state == top/bottom or left/right, or a combination of one of the two
    case "$movement_direction" in
      "top" )
        if [[ "$src_window_tiling_state" == "bottom" ]]; then
          dst_window_tiling_state="maximized"
        elif [[ "$src_window_tiling_state" =~ "bottom" ]]; then
          dst_window_tiling_state="${src_window_tiling_state/#bottom/}"  # prefix!
        else
          dst_window_tiling_state="${src_window_tiling_state/#top/}top"
        fi
        ;;
      "bottom" )
        if [[ "$src_window_tiling_state" == "top" ]]; then
          dst_window_tiling_state="maximized"
        elif [[ "$src_window_tiling_state" =~ "top" ]]; then
          dst_window_tiling_state="${src_window_tiling_state/#top/}"  # prefix!
        else
          dst_window_tiling_state="${src_window_tiling_state/#bottom/}bottom"
        fi
        ;;
      "left" )
        if [[ "$src_window_tiling_state" =~ "left" ]]; then
          dst_window_tiling_state="${src_window_tiling_state/%left/right}"  # suffix!
          hop_screen="true"
        elif [[ "$src_window_tiling_state" == "right" ]]; then
          dst_window_tiling_state="maximized"
        elif [[ "$src_window_tiling_state" =~ "right" ]]; then
          dst_window_tiling_state="${src_window_tiling_state/%right/}"  # suffix!
        else
          dst_window_tiling_state="${src_window_tiling_state/%left/}left"  # suffix!
        fi
        ;;
      "right" )
        if [[ "$src_window_tiling_state" =~ right ]]; then
          echo move
          dst_window_tiling_state="${src_window_tiling_state/%right/left}"  # suffix!
          hop_screen="true"
        elif [[ "$src_window_tiling_state" == "left" ]]; then
          dst_window_tiling_state="maximized"
        elif [[ "$src_window_tiling_state" =~ "left" ]]; then
          dst_window_tiling_state="${src_window_tiling_state/%left/}"  # suffix!
        else
          dst_window_tiling_state="${src_window_tiling_state/%right/}right"  # suffix!
        fi
        ;;
      * )
        echo "Unknown movement direction."
        exit 1
    esac
  fi
fi
echo "Target window tiling: $dst_window_tiling_state"

if [[ -z "$dst_window_tiling_state" ]]; then  # sanity check
  echo "Erroneous tiling decision"
  exit 1
fi


# find the monitor to the left/right of the monitor the window is on (similar as above)

if [[ "$hop_screen" == "true" ]]; then
  echo "Moving to $movement_direction monitor."
  dst_monitor_found=0
  while read line; do  # loop over monitors (see @done)
    dst_monitor_properties=( $(echo "$line" | sed "s/.* \([[:digit:]]\+x[[:digit:]]\++[[:digit:]]\++[[:digit:]]\+\) .*/\1/" | tr 'x' ' ' | tr '+' ' ') )  # we need the regex here because the number of words in the string can vary depending on if the monitor is the primary monitor
    dst_monitor_width=${dst_monitor_properties[0]}
    dst_monitor_height=${dst_monitor_properties[1]}
    dst_monitor_left=${dst_monitor_properties[2]}
    dst_monitor_top=${dst_monitor_properties[3]}
    dst_monitor_right=$((dst_monitor_left + dst_monitor_width))
    dst_monitor_bottom=$((dst_monitor_top + dst_monitor_height))
    if [[ "$movement_direction" == "right" ]] && [[ "$dst_monitor_left" -eq "$src_monitor_right" ]]; then
      dst_monitor_found=1
      break
    elif [[ "$movement_direction" == "left" ]] && [[ "$dst_monitor_right" -eq "$src_monitor_left" ]]; then
      dst_monitor_found=1
      break
    fi
  done <<< "$xrandr_connected_monitors"
  if [[ "$dst_monitor_found" -ne "1" ]]; then
    echo "No monitors to the $movement_direction side of the source monitor."
    exit 0
  fi
  # correct the available space due to panels
  panels=$(wmctrl -lG | grep -E "$panels_regex")
  while read line; do  # loop over panels (see @done)
    panel_properties=( $line )
    panel_left=${panel_properties[2]}
    panel_top=${panel_properties[3]}
    panel_width=${panel_properties[4]}
    panel_height=${panel_properties[5]}
    panel_right=$((panel_left + panel_width))
    panel_bottom=$((panel_top + panel_height))
    if [[ "$panel_left" -ge "$dst_monitor_left" &&
          "$panel_right" -le "$dst_monitor_right" &&
          "$panel_top" -ge "$dst_monitor_top" &&
          "$panel_bottom" -le "$dst_monitor_bottom" ]]; then
      if [[ "$panel_width" -ge "$panel_height" ]]; then  # horizontal panel
        echo "Subtracting height of panel \"${panel_properties[7]}\" from destination monitor."
        dst_monitor_height=$((dst_monitor_height - panel_height))
        if [[ "$panel_top" -eq "$dst_monitor_top" ]]; then
          dst_monitor_top=$((dst_monitor_top + panel_height))
        elif [[ "$panel_bottom" -eq "$dst_monitor_bottom" ]]; then
          dst_monitor_bottom=$((dst_monitor_bottom - panel_height))
        else
          echo "Panel is neither on top nor bottom of monitor."
        fi
      else  # vertical panel
        echo "Subtracting width of panel \"${panel_properties[7]}\" from destination monitor."
        dst_monitor_width=$((dst_monitor_width - panel_width))
        if [[ "$panel_left" -eq "$dst_monitor_left" ]]; then
          dst_monitor_left=$((dst_monitor_left + panel_width))
        elif [[ "$panel_right" -eq "$dst_monitor_right" ]]; then
          dst_monitor_right=$((dst_monitor_right - panel_width))
          echo "Panel is neither on left nor right of monitor."
        fi
      fi
    fi
  done <<< "$panels"

  echo "Geometry of selected destination monitor: ${dst_monitor_width}x${dst_monitor_height}+${dst_monitor_left}+${dst_monitor_top}"
else
  dst_monitor_width=$src_monitor_width
  dst_monitor_height=$src_monitor_height
  dst_monitor_left=$src_monitor_left
  dst_monitor_top=$src_monitor_top
  dst_monitor_right=$src_monitor_right
  dst_monitor_bottom=$src_monitor_bottom

  echo "Staying on the same monitor."
fi


# calculate the target position on the destination monitor

dst_monitor_half_width=$((dst_monitor_width / 2))
dst_monitor_half_height=$((dst_monitor_height / 2))

dst_window_rel_left="$src_window_rel_left"
dst_window_rel_top="$src_window_rel_top"
dst_window_width="$src_window_width"
dst_window_height="$src_window_height"
if [[ "$dst_window_tiling_state" =~ top ]]; then
  dst_window_rel_top=0
  dst_window_height="$dst_monitor_half_height"
elif [[ "$dst_window_tiling_state" =~ bottom ]]; then
  dst_window_rel_top="$dst_monitor_half_height"
  dst_window_height="$dst_monitor_half_height"
fi
if [[ "$dst_window_tiling_state" =~ left ]]; then
  dst_window_rel_left=0
  dst_window_width="$dst_monitor_half_width"
elif [[ "$dst_window_tiling_state" =~ right ]]; then
  dst_window_rel_left="$dst_monitor_half_width"
  dst_window_width="$dst_monitor_half_width"
fi
# monitor relative to X display relative
dst_window_abs_left=$((dst_window_rel_left + dst_monitor_left))
dst_window_abs_top=$((dst_window_rel_top + dst_monitor_top))

# disable maximized, so we can move the window
if [[ "$src_window_horz_maxed" -ne 0 || "$src_window_vert_maxed" -ne 0 ]]; then
  wmctrl -i -r "$window_id" -b remove,maximized_horz,maximized_vert
fi

# before we can calculate the width and height we need to update the relative window offset which e.g. are different when maximized
if [[ "$src_window_tiling_state" == "maximized" && "$dst_window_tiling_state" != "maximized" ]]; then
  window_info=$(xwininfo -id "$window_id")
  src_window_off_left=$(echo "$window_info" | awk '/Relative upper-left X:/ { print $4 }')
  src_window_off_top=$(echo "$window_info" | awk '/Relative upper-left Y:/ { print $4 }')
  if [[ "$src_window_off_left" -eq 0 ]]; then
    echo "This should not have happened: window offset is zero for non maximized window! Where is the border?"
    echo "$window_info"
    exit 1
  fi
fi

dst_window_abs_width=$((dst_window_width - 2*src_window_off_left))  # account for left and right border
dst_window_abs_height=$((dst_window_height - src_window_off_top - src_window_off_left))  # account for window decorations and bottom border
echo "Move window to ${dst_window_width}x${dst_window_height}+${dst_window_abs_left}+${dst_window_abs_top} ($dst_window_rel_left+$dst_window_rel_top)"

# move and resize window
wmctrl -i -r "$window_id" -e "0,$dst_window_abs_left,$dst_window_abs_top,$dst_window_abs_width,$dst_window_abs_height"

# we need a little delay before setting the maximized states, otherwise the maximized states are sometimes not set
# TODO is there a better way?
sleep 0.1

# Maximize window again, if it was before
if [[ "$dst_window_tiling_state" == "maximized" ]]; then
  echo "Maximize full"
  wmctrl -i -r "$window_id" -b add,maximized_vert,maximized_horz
elif [[ "$dst_window_tiling_state" == "left" || "$dst_window_tiling_state" == "right" ]]; then
  echo "Maximize vertically"
  wmctrl -i -r "$window_id" -b add,maximized_vert
elif [[ "$dst_window_tiling_state" == "top" || "$dst_window_tiling_state" == "bottom" ]]; then
  echo "Maximized horizontally"
  wmctrl -i -r "$window_id" -b add,maximized_horz
fi


exit 0
