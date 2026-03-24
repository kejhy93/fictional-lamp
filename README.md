# bash-progress-bar

A lightweight progress bar for Bash and PowerShell that pins itself to the last line of the terminal. Regular script output scrolls normally above it without ever overwriting the bar.

## Features

- Pinned to the last terminal line via ANSI scroll region — output above never clobbers it
- Auto-scales bar width to the current terminal width
- Optional label (left-aligned, up to 20 chars)
- Spinner with 5 built-in styles (braille, classic, arrows, bounce, circle)
- Synchronous mode: caller drives the bar each iteration
- Async mode: bar animates in the background while the calculation runs freely
- No external dependencies beyond the shell itself

## Bash

### Requirements

`bash` and `tput` (part of `ncurses`, standard on Linux/macOS).

### Synchronous usage

Source the script and drive the bar from your own loop:

```bash
source progress_bar.sh

progress_bar_init

total=100
for (( i=0; i<=total; i++ )); do
    echo "Processing item $i..."
    progress_bar "$i" "$total" "Installing"
    sleep 0.05
done

progress_bar_done
```

### Async usage

The bar runs in a background process and animates on its own. Your code just calls `progress_bar_update` whenever progress changes:

```bash
source progress_bar.sh

progress_bar_start 100 "Installing"

for (( i=0; i<=100; i++ )); do
    do_work "$i"           # variable-length work — bar keeps spinning
    progress_bar_update "$i"
    echo "Step $i done"
done

progress_bar_stop
```

### API

**Synchronous**

| Function | Signature | Description |
|---|---|---|
| `progress_bar_init` | `progress_bar_init` | Reserve the last terminal line. Call once before the loop. |
| `progress_bar` | `progress_bar <current> <total> [label]` | Draw the bar. Call on each iteration. |
| `progress_bar_done` | `progress_bar_done` | Restore the terminal. Call once after the loop. |

**Async**

| Function | Signature | Description |
|---|---|---|
| `progress_bar_start` | `progress_bar_start <total> [label]` | Start the background renderer. |
| `progress_bar_update` | `progress_bar_update <current>` | Send a progress value from the calculation. |
| `progress_bar_stop` | `progress_bar_stop` | Stop the renderer and restore the terminal. |

**Spinner**

| Function | Signature | Description |
|---|---|---|
| `progress_bar_set_spinner` | `progress_bar_set_spinner <style>` | Switch spinner style. Resets the frame index. |

**Parameters for `progress_bar` / `progress_bar_start`:**

- `current` / `total` — current and total step count
- `label` _(optional)_ — text printed left of the bar, truncated/padded to 20 characters

**Spinner styles:**

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

### Running the demo

```bash
bash progress_bar.sh
```

## PowerShell

### Requirements

PowerShell 5.1+ on Windows 10 / Windows Terminal, or PowerShell 7+ on Linux/macOS. Requires a VT-compatible terminal (Windows Terminal, iTerm2, most Linux terminals).

### Synchronous usage

Dot-source the script and drive the bar from your own loop:

```powershell
. ./progress_bar.ps1

Initialize-ProgressBar

$total = 100
for ($i = 0; $i -le $total; $i++) {
    Write-Host "Processing item $i..."
    Write-ProgressBar -Current $i -Total $total -Label "Installing"
    Start-Sleep -Milliseconds 50
}

Complete-ProgressBar
```

### Async usage

The bar runs in a background runspace and animates on its own. Your code just calls `Update-ProgressBar` whenever progress changes:

```powershell
. ./progress_bar.ps1

Start-ProgressBar -Total 100 -Label "Installing"

for ($i = 0; $i -le 100; $i++) {
    Invoke-Work $i           # variable-length work — bar keeps spinning
    Update-ProgressBar -Current $i
    Write-Host "Step $i done"
}

Stop-ProgressBar
```

### API

**Synchronous**

| Function | Signature | Description |
|---|---|---|
| `Initialize-ProgressBar` | `Initialize-ProgressBar` | Reserve the last terminal line. Call once before the loop. |
| `Write-ProgressBar` | `Write-ProgressBar -Current n -Total n [-Label s]` | Draw the bar. Call on each iteration. |
| `Complete-ProgressBar` | `Complete-ProgressBar` | Restore the terminal. Call once after the loop. |

**Async**

| Function | Signature | Description |
|---|---|---|
| `Start-ProgressBar` | `Start-ProgressBar -Total n [-Label s]` | Start the background renderer (runspace). |
| `Update-ProgressBar` | `Update-ProgressBar -Current n` | Send a progress value from the calculation. |
| `Stop-ProgressBar` | `Stop-ProgressBar` | Stop the renderer and restore the terminal. |

**Spinner**

| Function | Signature | Description |
|---|---|---|
| `Set-ProgressBarSpinner` | `Set-ProgressBarSpinner [-Style s]` | Switch spinner style. Resets the frame index. |

**Parameters for `Write-ProgressBar` / `Start-ProgressBar`:**

- `-Current` / `-Total` — current and total step count
- `-Label` _(optional)_ — text printed left of the bar, truncated/padded to 20 characters

**Spinner styles:**

| Style | Preview |
|---|---|
| `Braille` _(default)_ | `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` |
| `Classic` | `\| / - \` |
| `Arrows` | `← ↑ → ↓` |
| `Bounce` | `▁ ▂ ▃ ▄ ▅ ▆ ▇ █ ▇ ▆ ▅ ▄ ▃ ▂` |
| `Circle` | `◐ ◓ ◑ ◒` |

```powershell
Set-ProgressBarSpinner -Style Classic
```

### Running the demo

```powershell
pwsh progress_bar.ps1
```

## How it works

### Synchronous mode

Both implementations use the same ANSI terminal mechanism:

1. **Init** sets the scroll region (`ESC[top;bottomr` / `tput csr`) to exclude the last row. Any `echo`/`Write-Host` output scrolls only within that region, leaving the last line untouched.
2. **Draw** saves the cursor (`ESC 7`), jumps to the last line (`ESC[row;colH`), draws the bar, then restores the cursor (`ESC 8`) — so regular output continues from exactly where it left off.
3. **Done** resets the scroll region to full height and clears the reserved line.

### Async mode

The async renderer runs independently of the main process/thread and must solve two extra problems:

**Correct terminal dimensions in a background context**

- **Bash**: background subshells have stdin redirected to `/dev/null`, which can prevent `tput lines`/`tput cols` from querying the terminal size (causing the bar to be drawn at the wrong row). The async renderer uses `stty size </dev/tty` instead, which reliably reads dimensions from any background process.
- **PowerShell**: `[Console]::WindowHeight` can return 0 inside a runspace. The dimensions are captured from the main thread at `Start-ProgressBar` time and stored in the shared state as a fallback.

**Preventing output from interleaving**

- **Bash**: the entire frame (save-cursor + jump + clear + bar + restore-cursor) is built into a single `printf` call and written to `/dev/tty` directly. One `printf` = one atomic write, so it cannot interleave character-by-character with the main process's `echo`.
- **PowerShell**: the frame is assembled into a single string and emitted with one `[Console]::Write` call. The runspace and main thread each produce one atomic write per operation, so escape sequences are never split.

Unicode bar characters (`█`, `░`, braille spinner) are built via string concatenation in both implementations — never with byte-oriented tools like `tr` — so multibyte UTF-8 characters are never corrupted.
