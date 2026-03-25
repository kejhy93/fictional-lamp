# Progress bar — Java

Pins a progress bar to the last terminal line while regular output scrolls above it.

## Requirements

Java 11+. No external libraries. Requires a VT-compatible terminal (standard on Linux/macOS; Windows Terminal on Windows).

## Compiling

```bash
cd java
javac ProgressBar.java
```

## Usage

### Synchronous

Call `init()` once, then `draw()` on each iteration, then `done()` when finished:

```java
ProgressBar.init();

int total = 100;
for (int i = 0; i <= total; i++) {
    System.out.println("Processing item " + i + "...");
    ProgressBar.draw(i, total, "Installing");
    Thread.sleep(50);
}

ProgressBar.done();
```

### Async

The bar animates in a daemon thread. Call `update()` to report progress and `log()` instead of `System.out.println` to avoid interleaving:

```java
ProgressBar.start(100, "Installing");

for (int i = 0; i <= 100; i++) {
    doWork(i);
    ProgressBar.update(i);
    ProgressBar.log("Step " + i + " done");
}

ProgressBar.stop();
```

## API

### Synchronous

| Method | Signature | Description |
|---|---|---|
| `init` | `ProgressBar.init()` | Reserve the last terminal line. Call once before the loop. |
| `draw` | `ProgressBar.draw(current, total)` | Draw the bar without a label. |
| `draw` | `ProgressBar.draw(current, total, label)` | Draw the bar with a label. |
| `done` | `ProgressBar.done()` | Restore the terminal. Call once after the loop. |

### Async

| Method | Signature | Description |
|---|---|---|
| `start` | `ProgressBar.start(total)` | Start the background renderer thread (~20 fps). |
| `start` | `ProgressBar.start(total, label)` | Start with a label. |
| `update` | `ProgressBar.update(current)` | Report current progress from any thread. |
| `stop` | `ProgressBar.stop()` | Stop the renderer and restore the terminal. |

### Spinner

| Method | Signature | Description |
|---|---|---|
| `setSpinner` | `ProgressBar.setSpinner(SpinnerStyle.BRAILLE)` | Switch spinner style. Resets the frame index. |

**`SpinnerStyle` enum values:**

| Value | Preview |
|---|---|
| `BRAILLE` _(default)_ | `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏` |
| `CLASSIC` | `\| / - \` |
| `ARROWS` | `← ↑ → ↓` |
| `BOUNCE` | `▁ ▂ ▃ ▄ ▅ ▆ ▇ █ ▇ ▆ ▅ ▄ ▃ ▂` |
| `CIRCLE` | `◐ ◓ ◑ ◒` |

```java
ProgressBar.setSpinner(SpinnerStyle.CLASSIC);
```

### Color

| Method | Signature | Description |
|---|---|---|
| `setColor` | `ProgressBar.setColor(ColorMode.AUTO)` | Set color mode for the filled bar segment. |

**`ColorMode` enum values:**

| Value | Behavior |
|---|---|
| `AUTO` _(default)_ | Red < 33%, yellow 33–65%, green ≥ 66% |
| `NONE` | No color |
| `RED` \| `YELLOW` \| `GREEN` \| `CYAN` \| `BLUE` \| `MAGENTA` | Fixed color |

```java
ProgressBar.setColor(ColorMode.GREEN);  // always green
ProgressBar.setColor(ColorMode.NONE);   // disable color
```

### Log-safe output

| Method | Signature | Description |
|---|---|---|
| `log` | `ProgressBar.log(message)` | Safe `System.out.println` replacement during async bar usage. |

In async mode, `System.out.println` and the renderer thread write to the terminal concurrently. `log()` queues messages in a `BlockingQueue` so the renderer prints them before each frame. In sync mode it falls back to plain `System.out.println`.

## Running the demo

```bash
cd java
javac ProgressBar.java
java ProgressBar
```

## How it works

### Scroll region

`init()` writes `ESC[1;<rows-1>r` to restrict scrolling to all rows except the last. Subsequent `System.out.println` output scrolls within that region and never touches the reserved bottom line.

### Drawing the bar

Each `draw()` call builds a single string and writes it atomically to `/dev/tty`:

```
ESC 7                  — save cursor position
ESC[<rows>;1H          — jump to last row
ESC[2K                 — clear the line
<label> [████░░] NNN% <spinner>
ESC 8                  — restore cursor position
```

Writing to `/dev/tty` directly (via `FileOutputStream`) keeps bar output separate from `System.out`, which may be piped or redirected independently.

### Async renderer

A daemon thread loops at ~20 fps:

1. Drains the `BlockingQueue<String>` log queue, writing each message to `/dev/tty`
2. Reads the current progress value from a `volatile int`
3. Queries terminal size via `stty size` with stdin from `/dev/tty`
4. Builds and writes the bar frame as a single atomic write

`stop()` sets the running flag to false, joins the thread (with a 500 ms timeout), drains any remaining log messages to `System.out`, then calls `done()`.

### Terminal size

Terminal dimensions are queried by running `stty size` with stdin redirected from `/dev/tty`:

```java
new ProcessBuilder("stty", "size").redirectInput(new File("/dev/tty")).start()
```

This works from both the main thread and the daemon renderer thread, regardless of whether the JVM's own stdin is a terminal. Falls back to 24 rows × 80 cols if the query fails.
