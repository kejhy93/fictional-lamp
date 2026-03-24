# bash-progress-bar

A lightweight progress bar for Bash and PowerShell that pins itself to the last line of the terminal. Regular script output scrolls normally above it without ever overwriting the bar.

## Features

- Pinned to the last terminal line via ANSI scroll region — output above never clobbers it
- Auto-scales bar width to the current terminal width
- Optional label (left-aligned, up to 20 chars)
- Spinner with 5 built-in styles (braille, classic, arrows, bounce, circle)
- No external dependencies beyond the shell itself

## Bash

### Requirements

`bash` and `tput` (part of `ncurses`, standard on Linux/macOS).

### Usage

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
| `progress_bar_set_spinner` | `progress_bar_set_spinner <style>` | Switch spinner style. Resets the frame index. |

**Parameters for `progress_bar`:**

- `current` — current step (0 to `total`)
- `total` — total number of steps
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

### Usage

Dot-source the script into your own script, then wrap your work between `Initialize-ProgressBar` and `Complete-ProgressBar`:

```powershell
. ./progress_bar.ps1

Initialize-ProgressBar

$total = 100
for ($i = 0; $i -le $total; $i++) {
    Write-Host "Processing item $i..."   # scrolls normally above the bar
    Write-ProgressBar -Current $i -Total $total -Label "Installing"
    Start-Sleep -Milliseconds 50
}

Complete-ProgressBar
```

### API

| Function | Signature | Description |
|---|---|---|
| `Initialize-ProgressBar` | `Initialize-ProgressBar` | Call once before the first `Write-ProgressBar`. Reserves the last terminal line. |
| `Write-ProgressBar` | `Write-ProgressBar -Current n -Total n [-Label s]` | Draws the bar. Safe to call inside loops that also `Write-Host`. |
| `Complete-ProgressBar` | `Complete-ProgressBar` | Call once when finished. Restores the terminal to its normal state. |
| `Set-ProgressBarSpinner` | `Set-ProgressBarSpinner [-Style s]` | Switch spinner style. Resets the frame index. |

**Parameters for `Write-ProgressBar`:**

- `-Current` — current step (0 to `-Total`)
- `-Total` — total number of steps
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

Both implementations use the same ANSI terminal mechanism:

1. **Init** sets the scroll region (ANSI `ESC[top;bottomr` / `tput csr`) to exclude the last row. Any output will only ever scroll within that region, leaving the last line untouched.
2. **Draw** saves the cursor (`ESC 7` / `tput sc`), jumps to the last line (`ESC[row;colH` / `tput cup`), draws the bar, then restores the cursor (`ESC 8` / `tput rc`) — so regular output continues from exactly where it left off.
3. **Done** resets the scroll region to full height and clears the reserved line.

Unicode bar characters (`█`, `░`, braille spinner) are built via string concatenation in both implementations — never with byte-oriented tools like `tr` — so multibyte UTF-8 characters are never corrupted.
