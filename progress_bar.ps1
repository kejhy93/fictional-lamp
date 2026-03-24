#!/usr/bin/env pwsh

# Spinner state (script-scoped so it persists across calls)
$script:_pb_spin_idx = 0
$script:_pb_spin_chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
$script:_pb_esc = [char]27

# Initialize-ProgressBar
#   Call once before using Write-ProgressBar.
#   Shrinks the scroll region to exclude the last line, reserving it for the bar.
function Initialize-ProgressBar {
    $rows = [Console]::WindowHeight
    $esc = $script:_pb_esc
    # DECSTBM: set scroll region to rows 1..(rows-1), leaving last row reserved (1-based)
    [Console]::Write("${esc}[1;$($rows - 1)r")
    # Park cursor at bottom of scroll region
    [Console]::Write("${esc}[$($rows - 1);1H")
}

# Complete-ProgressBar
#   Call once after the last Write-ProgressBar to restore the terminal.
function Complete-ProgressBar {
    $rows = [Console]::WindowHeight
    $esc = $script:_pb_esc
    # Restore full scroll region
    [Console]::Write("${esc}[1;${rows}r")
    # Move to reserved line, clear it, park cursor above, emit fresh line
    [Console]::Write("${esc}[${rows};1H${esc}[2K${esc}[$($rows - 1);1H")
    [Console]::WriteLine()
}

# Write-ProgressBar -Current <n> -Total <n> [-Label <string>]
#   Current - current step (0..Total)
#   Total   - total number of steps
#   Label   - optional label printed before the bar (max 20 chars)
#
# Bar width auto-scales to the current terminal width.
# A spinner advances on each call to indicate activity.
# Call Initialize-ProgressBar before and Complete-ProgressBar after.
function Write-ProgressBar {
    param(
        [Parameter(Mandatory)][int]$Current,
        [Parameter(Mandatory)][int]$Total,
        [string]$Label = ""
    )

    $cols = [Console]::WindowWidth
    $rows = [Console]::WindowHeight
    $esc = $script:_pb_esc

    # Overhead without label: "[ bar ] NNN% ⠋" = 9 chars
    # Overhead with label:    "%-20s [ bar ] NNN% ⠋" = 30 chars
    $overhead = if ($Label) { 30 } else { 9 }
    $width = [Math]::Max(1, $cols - $overhead)

    $percent = [Math]::Floor($Current * 100 / $Total)
    $filled  = [Math]::Floor($Current * $width / $Total)
    $empty   = $width - $filled

    # String multiplication is character-level in .NET (safe for multibyte Unicode)
    $bar = ('█' * $filled) + ('░' * $empty)

    $spinner = $script:_pb_spin_chars[$script:_pb_spin_idx]
    $script:_pb_spin_idx = ($script:_pb_spin_idx + 1) % $script:_pb_spin_chars.Count

    # Build output: save cursor (ESC 7), jump to last line, erase, draw, restore (ESC 8)
    $pct = $percent.ToString().PadLeft(3)
    $out = "${esc}7${esc}[${rows};1H${esc}[2K"
    if ($Label) {
        $labelStr = $Label.Substring(0, [Math]::Min($Label.Length, 20)).PadRight(20)
        $out += "${labelStr} [${bar}] ${pct}% ${spinner}"
    } else {
        $out += "[${bar}] ${pct}% ${spinner}"
    }
    $out += "${esc}8"
    [Console]::Write($out)
}

# --- Demo ---
function demo_simple {
    $total = 50
    Initialize-ProgressBar
    Write-Host "Simple progress bar (other output won't disturb it):"
    for ($i = 0; $i -le $total; $i++) {
        Write-ProgressBar -Current $i -Total $total
        Start-Sleep -Milliseconds 50
    }
    Complete-ProgressBar
}

function demo_labeled {
    $steps = @("Downloading", "Extracting", "Installing", "Configuring")
    $total = 30
    Initialize-ProgressBar
    Write-Host "Labeled progress bars:"
    foreach ($label in $steps) {
        Write-Host "  Starting: $label"
        for ($i = 0; $i -le $total; $i++) {
            Write-ProgressBar -Current $i -Total $total -Label $label
            Start-Sleep -Milliseconds 30
        }
        Write-Host "  Done:     $label"
    }
    Complete-ProgressBar
}

demo_simple
demo_labeled
