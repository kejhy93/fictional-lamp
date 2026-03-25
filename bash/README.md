# Progress bar — Bash

Pins a progress bar to the last terminal line while regular `echo` output scrolls above it.

## Requirements

`bash` and `tput` (part of `ncurses`, standard on Linux/macOS).

## Usage

### Synchronous

Source the script and drive the bar from your own loop:

```bash
source bash/progress_bar.sh

progress_bar_init

total=100
for (( i=0; i<=total; i++ )); do
    echo "Processing item $i..."
    progress_bar "$i" "$total" "Installing"
    sleep 0.05
done

progress_bar_done
```

### Async

The bar runs in a background process and animates on its own. Call `progress_bar_update` whenever progress changes, and use `pb_log` instead of `echo` to avoid interleaving:

```bash
source bash/progress_bar.sh

progress_bar_start 100 "Installing"

for (( i=0; i<=100; i++ )); do
    do_work "$i"
    progress_bar_update "$i"
    pb_log "Step $i done"
done

progress_bar_stop
```

## API

### Synchronous

| Function | Signature | Description |
|---|---|---|
| `progress_bar_init` | `progress_bar_init` | Reserve the last terminal line. Call once before the loop. |
| `progress_bar` | `progress_bar <current> <total> [label]` | Draw the bar. Call on each iteration. |
| `progress_bar_done` | `progress_bar_done` | Restore the terminal. Call once after the loop. |

### Async

| Function | Signature | Description |
|---|---|---|
| `progress_bar_start` | `progress_bar_start <total> [label]` | Start the background renderer. |
| `progress_bar_update` | `progress_bar_update <current>` | Send a progress value from the calculation. |
| `progress_bar_stop` | `progress_bar_stop` | Stop the renderer and restore the terminal. |

### Spinner

| Function | Signature | Description |
|---|---|---|
| `progress_bar_set_spinner` | `progress_bar_set_spinner <style>` | Switch spinner style. Resets the frame index. |

**Styles:**

| Style | Preview |
|---|---|
| `braille` _(default)_ | `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` |
| `classic` | `\| / - \` |
| `arrows` | `← ↑ → ↓` |
| `bounce` | `▁ ▂ ▃ ▄ ▅ ▆ ▇ █ ▇ ▆ ▅ ▄ ▃ ▂` |
| `circle` | `◐ ◓ ◑ ◒` |

```bash
progress_bar_set_spinner classic
```

### Color

| Function | Signature | Description |
|---|---|---|
| `progress_bar_set_color` | `progress_bar_set_color <mode>` | Set color mode for the filled bar segment. |

| Mode | Behavior |
|---|---|
| `auto` _(default)_ | Red < 33%, yellow 33–65%, green ≥ 66% |
| `none` | No color |
| `red` \| `yellow` \| `green` \| `cyan` \| `blue` \| `magenta` | Fixed color |

```bash
progress_bar_set_color green   # always green
progress_bar_set_color none    # disable color
```

### Log-safe output

| Function | Signature | Description |
|---|---|---|
| `pb_log` | `pb_log <message>` | Safe `echo` replacement during async bar usage. |

In async mode, `echo` and the background renderer write to the terminal concurrently. `pb_log` routes output through the renderer so all terminal writes are serialized. In sync mode it falls back to plain `echo`.

## Running the demo

```bash
bash bash/progress_bar.sh
```

## How it works

### Scroll region

`progress_bar_init` calls `tput csr 0 $((rows-2))` to restrict scrolling to all rows except the last. Any subsequent `echo` output pushes content upward within that region and never touches the reserved bottom line.

### Drawing the bar

Each `progress_bar` call:
1. Saves the cursor with `tput sc`
2. Jumps to the last row with `tput cup $((rows-1)) 0`
3. Clears the line with `tput el`
4. Prints the bar
5. Restores the cursor with `tput rc`

The calling loop's `echo` statements continue scrolling from wherever the cursor was before the call, unaffected.

### Async renderer

The background process writes directly to `/dev/tty` rather than stdout. This keeps bar output separate from the main process's stdout and allows the renderer to query terminal dimensions with `stty size </dev/tty` even when its own stdin is `/dev/null`.

Each rendered frame is a single `printf` call — one atomic write — so the escape sequences that make up a frame (save-cursor, position, clear, bar, restore-cursor) are never split by concurrent writes from the main process.

`pb_log` sends messages over a named FIFO (file descriptor 7). The renderer flushes the FIFO before drawing each frame, ensuring log lines always appear above the bar.

### Unicode

Bar characters (`█`, `░`) and braille spinner frames are built with bash string-append loops. `tr` is byte-oriented and would corrupt multibyte UTF-8 sequences, so it is never used for this.
