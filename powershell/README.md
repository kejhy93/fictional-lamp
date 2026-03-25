# Progress bar — PowerShell

Pins a progress bar to the last terminal line while regular `Write-Host` output scrolls above it.

## Requirements

PowerShell 5.1+ on Windows 10 / Windows Terminal, or PowerShell 7+ on Linux/macOS. Requires a VT-compatible terminal (Windows Terminal, iTerm2, most Linux terminals).

## Usage

### Synchronous

Dot-source the script and drive the bar from your own loop:

```powershell
. ./powershell/progress_bar.ps1

Initialize-ProgressBar

$total = 100
for ($i = 0; $i -le $total; $i++) {
    Write-Host "Processing item $i..."
    Write-ProgressBar -Current $i -Total $total -Label "Installing"
    Start-Sleep -Milliseconds 50
}

Complete-ProgressBar
```

### Async

The bar runs in a background runspace and animates on its own. Call `Update-ProgressBar` whenever progress changes, and use `Write-PBLog` instead of `Write-Host` to avoid interleaving:

```powershell
. ./powershell/progress_bar.ps1

Start-ProgressBar -Total 100 -Label "Installing"

for ($i = 0; $i -le 100; $i++) {
    Invoke-Work $i
    Update-ProgressBar -Current $i
    Write-PBLog "Step $i done"
}

Stop-ProgressBar
```

## API

### Synchronous

| Function | Signature | Description |
|---|---|---|
| `Initialize-ProgressBar` | `Initialize-ProgressBar` | Reserve the last terminal line. Call once before the loop. |
| `Write-ProgressBar` | `Write-ProgressBar -Current n -Total n [-Label s]` | Draw the bar. Call on each iteration. |
| `Complete-ProgressBar` | `Complete-ProgressBar` | Restore the terminal. Call once after the loop. |

### Async

| Function | Signature | Description |
|---|---|---|
| `Start-ProgressBar` | `Start-ProgressBar -Total n [-Label s]` | Start the background renderer (runspace). |
| `Update-ProgressBar` | `Update-ProgressBar -Current n` | Send a progress value from the calculation. |
| `Stop-ProgressBar` | `Stop-ProgressBar` | Stop the renderer and restore the terminal. |

### Spinner

| Function | Signature | Description |
|---|---|---|
| `Set-ProgressBarSpinner` | `Set-ProgressBarSpinner [-Style s]` | Switch spinner style. Resets the frame index. |

**Styles:**

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

### Color

| Function | Signature | Description |
|---|---|---|
| `Set-ProgressBarColor` | `Set-ProgressBarColor [-Mode s]` | Set color mode for the filled bar segment. |

| Mode | Behavior |
|---|---|
| `Auto` _(default)_ | Red < 33%, yellow 33–65%, green ≥ 66% |
| `None` | No color |
| `Red` \| `Yellow` \| `Green` \| `Cyan` \| `Blue` \| `Magenta` | Fixed color |

```powershell
Set-ProgressBarColor -Mode Green   # always green
Set-ProgressBarColor -Mode None    # disable color
```

### Log-safe output

| Function | Signature | Description |
|---|---|---|
| `Write-PBLog` | `Write-PBLog <message>` | Safe `Write-Host` replacement during async bar usage. |

In async mode, `Write-Host` and the background runspace write to the terminal concurrently. `Write-PBLog` routes output through the renderer so all terminal writes are serialized. In sync mode it falls back to plain `Write-Host`.

## Running the demo

```powershell
pwsh powershell/progress_bar.ps1
```

## How it works

### Scroll region

`Initialize-ProgressBar` writes `ESC[1;<rows-1>r` to restrict scrolling to all rows except the last. Subsequent `Write-Host` output scrolls within that region and never touches the reserved bottom line.

### Drawing the bar

Each `Write-ProgressBar` call:
1. Saves the cursor with `ESC 7`
2. Jumps to the last row with `ESC[<rows>;1H`
3. Clears the line with `ESC[2K`
4. Prints the bar
5. Restores the cursor with `ESC 8`

### Async renderer

The runspace captures terminal dimensions (`[Console]::WindowHeight` / `[Console]::WindowWidth`) from the main thread at `Start-ProgressBar` time and stores them in a shared hashtable. This is a fallback for runspace contexts where `[Console]` property reads can return 0.

Each rendered frame is assembled into a single string and written with one `[Console]::Write` call, making it atomic with respect to other single-call writes from the main thread.

`Write-PBLog` adds messages to a synchronized queue. The renderer drains the queue before drawing each frame, ensuring log lines always appear above the bar.
