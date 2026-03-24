# bash-progress-bar

A lightweight, dependency-free bash progress bar that pins itself to the last line of the terminal. Regular script output scrolls normally above it without ever overwriting the bar.

## Features

- Pinned to the last terminal line via `tput csr` (scroll region) — output above never clobbers it
- Auto-scales bar width to the current terminal width
- Optional label (left-aligned, up to 20 chars)
- Braille spinner that advances on every call to indicate activity
- Pure bash + `tput` — no external dependencies beyond `ncurses`

## Usage

Source the script into your own script, then wrap your work between `progress_bar_init` and `progress_bar_done`:

```bash
source progress_bar.sh

progress_bar_init

total=100
for (( i=0; i<=total; i++ )); do
    echo "Processing item $i..."   # scrolls normally above the bar
    progress_bar "$i" "$total" "Installing"
    sleep 0.05
done

progress_bar_done
```

### API

| Function | Signature | Description |
|---|---|---|
| `progress_bar_init` | `progress_bar_init` | Call once before the first `progress_bar`. Reserves the last terminal line. |
| `progress_bar` | `progress_bar <current> <total> [label]` | Draws the bar. Safe to call inside loops that also `echo`. |
| `progress_bar_done` | `progress_bar_done` | Call once when finished. Restores the terminal to its normal state. |

**Parameters for `progress_bar`:**

- `current` — current step (0 to `total`)
- `total` — total number of steps
- `label` _(optional)_ — text printed left of the bar, truncated/padded to 20 characters

### Running the demo

```bash
bash progress_bar.sh
```

This runs two demos: a simple unlabeled bar and a multi-phase labeled bar.

## How it works

`progress_bar_init` calls `tput csr 0 $(( rows - 2 ))` to shrink the terminal scroll region, excluding the last row. Any `echo` or `printf` output will only ever scroll within that region, leaving the last line untouched.

`progress_bar` uses `tput sc` to save the cursor, jumps to the last line with `tput cup`, draws the bar, then restores the cursor with `tput rc` — so regular output continues from exactly where it left off.

`progress_bar_done` resets the scroll region to full height and clears the reserved line.
