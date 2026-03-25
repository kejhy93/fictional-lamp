# bash-progress-bar

A lightweight progress bar that pins itself to the last line of the terminal. Regular script output scrolls normally above it without ever overwriting the bar.

![demo](demo.gif)

## Features

- Pinned to the last terminal line via ANSI scroll region — output above never clobbers it
- Auto-scales bar width to the current terminal width
- Optional label (left-aligned, up to 20 chars)
- Spinner with 5 built-in styles (braille, classic, arrows, bounce, circle)
- Color modes: auto (percent-based), fixed, or none
- Synchronous and async modes
- No external dependencies beyond the language runtime

## Languages

| Language | File | README |
|---|---|---|
| Bash | `bash/progress_bar.sh` | [bash/README.md](bash/README.md) |
| PowerShell | `powershell/progress_bar.ps1` | [powershell/README.md](powershell/README.md) |
| Java | `java/ProgressBar.java` | [java/README.md](java/README.md) |

## How it works

All implementations use the same ANSI terminal mechanism:

1. **Init** sets the scroll region (`ESC[top;bottomr`) to exclude the last row. Output scrolls only within that region, leaving the last line untouched.
2. **Draw** saves the cursor (`ESC 7`), jumps to the last line (`ESC[row;colH`), draws the bar, then restores the cursor (`ESC 8`) — so regular output resumes from exactly where it left off.
3. **Done** resets the scroll region to full height and clears the reserved line.

In async mode the renderer runs in the background (subprocess in Bash, runspace in PowerShell, daemon thread in Java) and animates at ~20 fps independently of the calling code. A log queue serializes terminal writes so output never interleaves with the bar.

## Regenerating the demo GIF

```bash
./generate_demo.sh
```

Requires `vhs`, `ffmpeg`, and `ttyd`. The script prints install instructions if any are missing.
