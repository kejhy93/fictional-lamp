#!/usr/bin/env bash

# Spinner state (global so it persists across calls)
_pb_spin_idx=0
_pb_spin_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# progress_bar_init
#   Call once before using progress_bar.
#   Shrinks the scroll region to exclude the last line, reserving it for the bar.
progress_bar_init() {
    local rows
    rows=$(tput lines 2>/dev/null || echo 24)
    tput csr 0 $(( rows - 2 ))  # scroll region: all rows except the last
    tput cup $(( rows - 2 )) 0  # park cursor at bottom of scroll region
}

# progress_bar_done
#   Call once after the last progress_bar to restore the terminal.
progress_bar_done() {
    local rows
    rows=$(tput lines 2>/dev/null || echo 24)
    tput csr 0 $(( rows - 1 ))  # restore full scroll region
    tput cup $(( rows - 1 )) 0  # move to reserved line
    tput el                      # clear it
    tput cup $(( rows - 2 )) 0  # park cursor above
    echo                         # ensure fresh line
}

# progress_bar <current> <total> [label]
#   current - current step (0..total)
#   total   - total number of steps
#   label   - optional label printed before the bar (max 20 chars)
#
# Bar width auto-scales to the current terminal width.
# A spinner rotates on each call to indicate activity.
# Call progress_bar_init before and progress_bar_done after.
progress_bar() {
    local current=$1
    local total=$2
    local label=${3:-""}

    local cols rows
    cols=$(tput cols 2>/dev/null || echo 80)
    rows=$(tput lines 2>/dev/null || echo 24)

    # Overhead without label: "[" + bar + "] NNN% ⠋" = 9 chars
    # Overhead with label:    "%-20s [" + bar + "] NNN% ⠋" = 30 chars
    local overhead
    if [[ -n "$label" ]]; then
        overhead=30
    else
        overhead=9
    fi
    local width=$(( cols - overhead ))
    (( width < 1 )) && width=1

    local percent=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))

    local bar="" i
    for (( i=0; i<filled; i++ )); do bar+='█'; done
    for (( i=0; i<empty;  i++ )); do bar+='░'; done

    local spinner="${_pb_spin_chars[$_pb_spin_idx]}"
    _pb_spin_idx=$(( (_pb_spin_idx + 1) % ${#_pb_spin_chars[@]} ))

    tput sc                          # save cursor
    tput cup $(( rows - 1 )) 0      # jump to reserved last line
    tput el                          # clear line
    if [[ -n "$label" ]]; then
        printf "%-20s [%s] %3d%% %s" "$label" "$bar" "$percent" "$spinner"
    else
        printf "[%s] %3d%% %s" "$bar" "$percent" "$spinner"
    fi
    tput rc                          # restore cursor
}

# --- Demo ---
demo_simple() {
    local total=50
    progress_bar_init
    echo "Simple progress bar (other output won't disturb it):"
    for (( i=0; i<=total; i++ )); do
        progress_bar "$i" "$total"
        sleep 0.05
    done
    progress_bar_done
}

demo_labeled() {
    local steps=("Downloading" "Extracting" "Installing" "Configuring")
    local total=30
    progress_bar_init
    echo "Labeled progress bars:"
    for label in "${steps[@]}"; do
        echo "  Starting: $label"
        for (( i=0; i<=total; i++ )); do
            progress_bar "$i" "$total" "$label"
            sleep 0.03
        done
        echo "  Done:     $label"
    done
    progress_bar_done
}

demo_simple
demo_labeled
