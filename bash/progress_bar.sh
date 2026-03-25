#!/usr/bin/env bash

# Spinner state (global so it persists across calls)
_pb_spin_idx=0
_pb_spin_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# Color state
_pb_color_mode=auto  # auto | none | <fixed>
_pb_color_code=""    # ANSI color escape for fixed mode

# Async state
_pb_async_file=""
_pb_async_pid=""
_pb_log_pipe=""

# progress_bar_set_spinner <style>
#   Switch spinner style at any time (resets frame index).
#   Styles:
#     braille (default)  ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
#     classic            | / - \
#     arrows             ← ↑ → ↓
#     bounce             ▁ ▂ ▃ ▄ ▅ ▆ ▇ █ ▇ ▆ ▅ ▄ ▃ ▂
#     circle             ◐ ◓ ◑ ◒
progress_bar_set_spinner() {
    _pb_spin_idx=0
    case "$1" in
        classic) _pb_spin_chars=('|' '/' '-' '\')                                                        ;;
        arrows)  _pb_spin_chars=('←' '↑' '→' '↓')                                                       ;;
        bounce)  _pb_spin_chars=('▁' '▂' '▃' '▄' '▅' '▆' '▇' '█' '▇' '▆' '▅' '▄' '▃' '▂')            ;;
        circle)  _pb_spin_chars=('◐' '◓' '◑' '◒')                                                       ;;
        braille|*) _pb_spin_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')                        ;;
    esac
}

# progress_bar_set_color <mode>
#   Set the color mode for the filled bar segment.
#   Modes:
#     auto (default)  Red <33%, yellow 33-65%, green >=66%
#     none            No color
#     red | yellow | green | cyan | blue | magenta  Fixed color
progress_bar_set_color() {
    local ESC=$'\033'
    _pb_color_mode="${1:-auto}"
    case "$_pb_color_mode" in
        none|auto) _pb_color_code="" ;;
        red)     _pb_color_code="${ESC}[31m" ;;
        yellow)  _pb_color_code="${ESC}[33m" ;;
        green)   _pb_color_code="${ESC}[32m" ;;
        cyan)    _pb_color_code="${ESC}[36m" ;;
        blue)    _pb_color_code="${ESC}[34m" ;;
        magenta) _pb_color_code="${ESC}[35m" ;;
        *)       _pb_color_mode=auto; _pb_color_code="" ;;
    esac
}

# pb_log <message>
#   Safe replacement for echo during async progress bar usage.
#   In async mode: routes output through the renderer to prevent interleaving.
#   In sync mode: behaves exactly like echo.
pb_log() {
    if [[ -n "$_pb_log_pipe" ]]; then
        printf '%s\n' "$*" >&7
    else
        echo "$@"
    fi
}

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

    local ESC=$'\033'
    local color=""
    if [[ "$_pb_color_mode" == auto ]]; then
        if   (( percent >= 66 )); then color="${ESC}[32m"
        elif (( percent >= 33 )); then color="${ESC}[33m"
        else                           color="${ESC}[31m"
        fi
    elif [[ "$_pb_color_mode" != none ]]; then
        color="$_pb_color_code"
    fi

    local filled_bar="" empty_bar="" i
    for (( i=0; i<filled; i++ )); do filled_bar+='█'; done
    for (( i=0; i<empty;  i++ )); do empty_bar+='░'; done
    local bar
    if [[ -n "$color" ]]; then
        bar="${color}${filled_bar}${ESC}[0m${empty_bar}"
    else
        bar="${filled_bar}${empty_bar}"
    fi

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

# --- Async API ---

# progress_bar_start <total> [label]
#   Starts the progress bar in the background (~20 fps).
#   The calculation runs freely and calls progress_bar_update to report progress.
#   Call progress_bar_stop when done.
progress_bar_start() {
    local total=$1
    local label=${2:-""}
    local spin_chars=("${_pb_spin_chars[@]}")  # snapshot at start time
    local color_mode="$_pb_color_mode"         # snapshot color settings at start time
    local color_code="$_pb_color_code"

    _pb_async_file=$(mktemp)
    printf '0\n' > "$_pb_async_file"

    # Create a named FIFO for log-safe output; open both ends on fd 7 before
    # forking so the subshell inherits the descriptor without blocking.
    _pb_log_pipe=$(mktemp -u /tmp/pb_log.XXXXXX)
    mkfifo "$_pb_log_pipe"
    exec 7<>"$_pb_log_pipe"

    progress_bar_init

    # Redirect subshell stdout to /dev/tty so the renderer writes directly to the
    # terminal without going through the main process's stdout (avoids interleaving).
    # stty size </dev/tty reliably queries terminal dimensions from a background process
    # (tput lines/cols can fail when stdin is /dev/null).
    (
        local ESC=$'\033'
        local spin_idx=0
        while [[ -f "$_pb_async_file" ]]; do
            # Flush any pending pb_log lines before drawing the bar
            local _pb_line
            while IFS= read -r -t 0.001 _pb_line <&7 2>/dev/null; do
                printf '%s\n' "$_pb_line" >/dev/tty
            done

            local current
            current=$(< "$_pb_async_file")
            if [[ "$current" =~ ^[0-9]+$ ]]; then
                local rows cols
                { read -r rows cols; } < <(stty size </dev/tty 2>/dev/null)
                : "${rows:=24}" "${cols:=80}"

                local overhead; [[ -n "$label" ]] && overhead=30 || overhead=9
                local width=$(( cols - overhead ))
                (( width < 1 )) && width=1

                local percent=$(( current * 100 / total ))
                local filled=$(( current * width / total ))

                local color=""
                if [[ "$color_mode" == auto ]]; then
                    if   (( percent >= 66 )); then color="${ESC}[32m"
                    elif (( percent >= 33 )); then color="${ESC}[33m"
                    else                           color="${ESC}[31m"
                    fi
                elif [[ "$color_mode" != none ]]; then
                    color="$color_code"
                fi

                local filled_bar="" empty_bar="" i
                for (( i=0; i<filled; i++ )); do filled_bar+='█'; done
                for (( i=0; i<width-filled; i++ )); do empty_bar+='░'; done
                local bar
                if [[ -n "$color" ]]; then
                    bar="${color}${filled_bar}${ESC}[0m${empty_bar}"
                else
                    bar="${filled_bar}${empty_bar}"
                fi

                local spinner="${spin_chars[$spin_idx]}"
                spin_idx=$(( (spin_idx + 1) % ${#spin_chars[@]} ))

                # Single printf = one atomic write; no tput process spawns.
                # ESC-7 / ESC-8 save and restore the cursor position.
                if [[ -n "$label" ]]; then
                    printf '\0337\033[%d;1H\033[2K%-20s [%s] %3d%% %s\0338' \
                        "$rows" "$label" "$bar" "$percent" "$spinner"
                else
                    printf '\0337\033[%d;1H\033[2K[%s] %3d%% %s\0338' \
                        "$rows" "$bar" "$percent" "$spinner"
                fi
            fi
            sleep 0.05
        done
    ) >/dev/tty &
    _pb_async_pid=$!
}

# progress_bar_update <current>
#   Send a progress update from the calculation.
progress_bar_update() {
    printf '%s\n' "$1" > "$_pb_async_file"
}

# progress_bar_stop
#   Stop the async progress bar and restore the terminal.
progress_bar_stop() {
    rm -f "$_pb_async_file"
    wait "$_pb_async_pid" 2>/dev/null
    # Drain any pb_log messages that arrived after the renderer's last tick
    local _pb_line
    while IFS= read -r -t 0.001 _pb_line <&7 2>/dev/null; do
        printf '%s\n' "$_pb_line"
    done
    exec 7>&-
    rm -f "$_pb_log_pipe"
    _pb_log_pipe=""
    progress_bar_done
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

demo_async() {
    local total=20
    progress_bar_start "$total" "Computing"
    pb_log "Async: bar animates while work runs at variable speed:"
    for (( i=0; i<=total; i++ )); do
        sleep 0.$(( RANDOM % 15 + 5 ))  # 50–150 ms of "work"
        progress_bar_update "$i"
        pb_log "  Step $i done"
    done
    progress_bar_stop
}

demo_simple
demo_labeled
demo_async
