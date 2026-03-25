#!/usr/bin/env pwsh

# Spinner state (script-scoped so it persists across calls)
$script:_pb_spin_idx = 0
$script:_pb_spin_chars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
$script:_pb_esc = [char]27

# Color state
$script:_pb_color_mode = 'auto'   # auto | none | <fixed>
$script:_pb_color_code = ''       # ANSI color string for fixed mode

# Async state
$script:_pb_sync         = $null
$script:_pb_runspace     = $null
$script:_pb_ps           = $null
$script:_pb_async_handle = $null
$script:_pb_log_queue    = $null

# Set-ProgressBarSpinner [-Style <string>]
#   Switch spinner style at any time (resets frame index).
#   Styles:
#     Braille (default)  ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
#     Classic            | / - \
#     Arrows             ← ↑ → ↓
#     Bounce             ▁ ▂ ▃ ▄ ▅ ▆ ▇ █ ▇ ▆ ▅ ▄ ▃ ▂
#     Circle             ◐ ◓ ◑ ◒
function Set-ProgressBarSpinner {
    param([string]$Style = 'Braille')
    $script:_pb_spin_idx = 0
    $script:_pb_spin_chars = switch ($Style) {
        'Classic' { @('|', '/', '-', '\') }
        'Arrows'  { @('←', '↑', '→', '↓') }
        'Bounce'  { @('▁', '▂', '▃', '▄', '▅', '▆', '▇', '█', '▇', '▆', '▅', '▄', '▃', '▂') }
        'Circle'  { @('◐', '◓', '◑', '◒') }
        default   { @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏') }
    }
}

# Set-ProgressBarColor [-Mode <string>]
#   Set the color mode for the filled bar segment.
#   Modes:
#     Auto (default)  Red <33%, yellow 33-65%, green >=66%
#     None            No color
#     Red | Yellow | Green | Cyan | Blue | Magenta  Fixed color
function Set-ProgressBarColor {
    param([string]$Mode = 'Auto')
    $esc = $script:_pb_esc
    $script:_pb_color_mode = $Mode
    $script:_pb_color_code = switch ($Mode) {
        'Red'     { "${esc}[31m" }
        'Yellow'  { "${esc}[33m" }
        'Green'   { "${esc}[32m" }
        'Cyan'    { "${esc}[36m" }
        'Blue'    { "${esc}[34m" }
        'Magenta' { "${esc}[35m" }
        default   { '' }
    }
}

# Write-PBLog [-Message] <string>
#   Safe replacement for Write-Host during async progress bar usage.
#   In async mode: routes output through the renderer to prevent interleaving.
#   In sync mode: behaves exactly like Write-Host.
function Write-PBLog {
    param([Parameter(ValueFromPipeline)][string]$Message)
    if ($script:_pb_log_queue) {
        $script:_pb_log_queue.Enqueue($Message)
    } else {
        Write-Host $Message
    }
}

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
    $filledBar = '█' * $filled
    $emptyBar  = '░' * $empty
    $color = switch ($script:_pb_color_mode) {
        'Auto' {
            if     ($percent -ge 66) { "${esc}[32m" }
            elseif ($percent -ge 33) { "${esc}[33m" }
            else                     { "${esc}[31m" }
        }
        'None' { '' }
        default { $script:_pb_color_code }
    }
    $bar = if ($color) { "${color}${filledBar}${esc}[0m${emptyBar}" } else { "${filledBar}${emptyBar}" }

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

# --- Async API ---

# Start-ProgressBar -Total <n> [-Label <string>]
#   Starts the progress bar in a background runspace (~20 fps).
#   The calculation runs freely and calls Update-ProgressBar to report progress.
#   Call Stop-ProgressBar when done.
function Start-ProgressBar {
    param(
        [Parameter(Mandatory)][int]$Total,
        [string]$Label = ""
    )

    # Capture dimensions in the main thread where Console is guaranteed available.
    # The runspace uses these as fallback if [Console]::WindowHeight returns 0.
    $initRows = [Console]::WindowHeight
    $initCols = [Console]::WindowWidth
    if ($initRows -le 0) { $initRows = 24 }
    if ($initCols -le 0) { $initCols = 80 }

    $script:_pb_log_queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $script:_pb_sync = [hashtable]::Synchronized(@{
        Current    = 0
        Total      = $Total
        Label      = $Label
        Running    = $true
        SpinIdx    = 0
        SpinChars  = $script:_pb_spin_chars
        Esc        = $script:_pb_esc
        InitRows   = $initRows
        InitCols   = $initCols
        ColorMode  = $script:_pb_color_mode
        ColorCode  = $script:_pb_color_code
        LogQueue   = $script:_pb_log_queue
    })

    Initialize-ProgressBar

    $script:_pb_runspace = [runspacefactory]::CreateRunspace()
    $script:_pb_runspace.Open()
    $script:_pb_runspace.SessionStateProxy.SetVariable('sync', $script:_pb_sync)

    $script:_pb_ps = [powershell]::Create()
    $script:_pb_ps.Runspace = $script:_pb_runspace
    [void]$script:_pb_ps.AddScript({
        while ($sync.Running) {
            # Flush any pending Write-PBLog messages before drawing the bar
            $msg = $null
            while ($sync.LogQueue.TryDequeue([ref]$msg)) {
                [Console]::WriteLine($msg)
            }

            $esc   = $sync.Esc
            $rows  = [Console]::WindowHeight
            $cols  = [Console]::WindowWidth
            # Fall back to dimensions captured in the main thread if the runspace
            # cannot access the console (returns 0 in some PS host environments).
            if ($rows -le 0) { $rows = $sync.InitRows }
            if ($cols -le 0) { $cols = $sync.InitCols }

            $label   = $sync.Label
            $current = $sync.Current
            $total   = $sync.Total

            $overhead = if ($label) { 30 } else { 9 }
            $width    = [Math]::Max(1, $cols - $overhead)
            $percent  = [Math]::Floor($current * 100 / $total)
            $filled   = [Math]::Floor($current * $width / $total)
            $empty    = $width - $filled

            $filledBar = '█' * $filled
            $emptyBar  = '░' * $empty
            $color = switch ($sync.ColorMode) {
                'Auto' {
                    if     ($percent -ge 66) { "${esc}[32m" }
                    elseif ($percent -ge 33) { "${esc}[33m" }
                    else                     { "${esc}[31m" }
                }
                'None' { '' }
                default { $sync.ColorCode }
            }
            $bar = if ($color) { "${color}${filledBar}${esc}[0m${emptyBar}" } else { "${filledBar}${emptyBar}" }

            $spinner  = $sync.SpinChars[$sync.SpinIdx]
            $sync.SpinIdx = ($sync.SpinIdx + 1) % $sync.SpinChars.Count

            $pct = $percent.ToString().PadLeft(3)
            $out = "${esc}7${esc}[${rows};1H${esc}[2K"
            if ($label) {
                $labelStr = $label.Substring(0, [Math]::Min($label.Length, 20)).PadRight(20)
                $out += "${labelStr} [${bar}] ${pct}% ${spinner}"
            } else {
                $out += "[${bar}] ${pct}% ${spinner}"
            }
            $out += "${esc}8"
            # Single [Console]::Write call — the entire escape sequence is one
            # atomic write, so it cannot interleave with the main thread's output.
            [Console]::Write($out)

            Start-Sleep -Milliseconds 50
        }
    })

    $script:_pb_async_handle = $script:_pb_ps.BeginInvoke()
}

# Update-ProgressBar -Current <n>
#   Send a progress update from the calculation.
function Update-ProgressBar {
    param([Parameter(Mandatory)][int]$Current)
    $script:_pb_sync.Current = $Current
}

# Stop-ProgressBar
#   Stop the async progress bar and restore the terminal.
function Stop-ProgressBar {
    $script:_pb_sync.Running = $false
    $script:_pb_ps.EndInvoke($script:_pb_async_handle)
    $script:_pb_ps.Dispose()
    $script:_pb_runspace.Close()
    $script:_pb_runspace.Dispose()
    # Drain any Write-PBLog messages that arrived after the renderer's last tick
    $msg = $null
    while ($script:_pb_log_queue.TryDequeue([ref]$msg)) {
        Write-Host $msg
    }
    $script:_pb_log_queue = $null
    Complete-ProgressBar
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

function demo_async {
    $total = 20
    Start-ProgressBar -Total $total -Label "Computing"
    Write-PBLog "Async: bar animates while work runs at variable speed:"
    for ($i = 0; $i -le $total; $i++) {
        Start-Sleep -Milliseconds (Get-Random -Minimum 50 -Maximum 150)  # variable "work"
        Update-ProgressBar -Current $i
        Write-PBLog "  Step $i done"
    }
    Stop-ProgressBar
}

demo_simple
demo_labeled
demo_async
