#!/usr/bin/env bash

# progress_bar <current> <total> [label]
#   current - current step (0..total)
#   total   - total number of steps
#   label   - optional label printed before the bar (max 20 chars)
#
# Bar width auto-scales to the current terminal width.
progress_bar() {
    local current=$1
    local total=$2
    local label=${3:-""}

    local cols
    cols=$(tput cols 2>/dev/null || echo 80)

    # Calculate bar width from available terminal columns.
    # Overhead without label: "[" + bar + "] NNN%" = 7 chars
    # Overhead with label:    "%-20s [" + bar + "] NNN%" = 28 chars
    local overhead
    if [[ -n "$label" ]]; then
        overhead=28
    else
        overhead=7
    fi
    local width=$(( cols - overhead ))
    (( width < 1 )) && width=1

    local percent=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))

    local bar="" i
    for (( i=0; i<filled; i++ )); do bar+='█'; done
    for (( i=0; i<empty;  i++ )); do bar+='░'; done

    if [[ -n "$label" ]]; then
        printf "\r%-20s [%s] %3d%%" "$label" "$bar" "$percent"
    else
        printf "\r[%s] %3d%%" "$bar" "$percent"
    fi
}

# --- Demo ---
demo_simple() {
    local total=50
    echo "Simple progress bar:"
    for (( i=0; i<=total; i++ )); do
        progress_bar "$i" "$total"
        sleep 0.05
    done
    echo    # newline after bar
}

demo_labeled() {
    local steps=("Downloading" "Extracting" "Installing" "Configuring")
    local total=30
    echo "Labeled progress bars:"
    for label in "${steps[@]}"; do
        for (( i=0; i<=total; i++ )); do
            progress_bar "$i" "$total" "$label"
            sleep 0.03
        done
        # no echo here — next label overwrites the same line
    done
    echo    # final newline after all labels
}

demo_simple
demo_labeled
