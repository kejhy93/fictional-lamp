import java.io.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/**
 * Java port of progress_bar.sh
 *
 * Reserves the last terminal line for a progress bar while the rest of the
 * screen scrolls normally, matching the bash implementation exactly.
 *
 * Sync API:
 *   ProgressBar.init();
 *   ProgressBar.draw(current, total);
 *   ProgressBar.draw(current, total, label);
 *   ProgressBar.done();
 *
 * Async API:
 *   ProgressBar.start(total);
 *   ProgressBar.start(total, label);
 *   ProgressBar.update(current);   // call from any thread
 *   ProgressBar.log("message");    // thread-safe println
 *   ProgressBar.stop();
 *
 * Configuration (call before init/start):
 *   ProgressBar.setSpinner(SpinnerStyle.BRAILLE);
 *   ProgressBar.setColor(ColorMode.AUTO);
 */
public class ProgressBar {

    // -------------------------------------------------------------------------
    // Spinner styles
    // -------------------------------------------------------------------------

    public enum SpinnerStyle { BRAILLE, CLASSIC, ARROWS, BOUNCE, CIRCLE }

    private static final String[][] SPINNER_FRAMES = {
        /* BRAILLE */ {"⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"},
        /* CLASSIC */ {"|","/","-","\\"},
        /* ARROWS  */ {"←","↑","→","↓"},
        /* BOUNCE  */ {"▁","▂","▃","▄","▅","▆","▇","█","▇","▆","▅","▄","▃","▂"},
        /* CIRCLE  */ {"◐","◓","◑","◒"},
    };

    // -------------------------------------------------------------------------
    // Color modes
    // -------------------------------------------------------------------------

    public enum ColorMode { AUTO, NONE, RED, YELLOW, GREEN, CYAN, BLUE, MAGENTA }

    private static final String RESET   = "\033[0m";
    private static final String C_RED   = "\033[31m";
    private static final String C_YEL   = "\033[33m";
    private static final String C_GRN   = "\033[32m";
    private static final String C_CYN   = "\033[36m";
    private static final String C_BLU   = "\033[34m";
    private static final String C_MAG   = "\033[35m";

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    private static String[]   spinFrames = SPINNER_FRAMES[SpinnerStyle.BRAILLE.ordinal()];
    private static int        spinIdx    = 0;
    private static ColorMode  colorMode  = ColorMode.AUTO;
    private static String     colorCode  = "";

    // Async state
    private static volatile int     asyncCurrent = 0;
    private static volatile boolean asyncRunning = false;
    private static Thread           asyncThread  = null;
    private static final BlockingQueue<String> logQueue = new LinkedBlockingQueue<>();

    // /dev/tty for writing directly to the terminal (avoids stdout interleaving)
    private static final OutputStream TTY;
    static {
        OutputStream out;
        try {
            out = new FileOutputStream("/dev/tty");
        } catch (IOException e) {
            out = System.out;
        }
        TTY = out;
    }

    // -------------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------------

    public static void setSpinner(SpinnerStyle style) {
        spinFrames = SPINNER_FRAMES[style.ordinal()];
        spinIdx = 0;
    }

    public static void setColor(ColorMode mode) {
        colorMode = mode;
        colorCode = switch (mode) {
            case RED     -> C_RED;
            case YELLOW  -> C_YEL;
            case GREEN   -> C_GRN;
            case CYAN    -> C_CYN;
            case BLUE    -> C_BLU;
            case MAGENTA -> C_MAG;
            default      -> "";
        };
    }

    // -------------------------------------------------------------------------
    // Terminal size  (reads from /dev/tty so it works in all contexts)
    // -------------------------------------------------------------------------

    private static int[] termSize() {
        try {
            Process p = new ProcessBuilder("stty", "size")
                    .redirectInput(new File("/dev/tty"))
                    .start();
            String out = new String(p.getInputStream().readAllBytes()).trim();
            p.waitFor();
            String[] parts = out.split("\\s+");
            if (parts.length == 2) {
                return new int[]{ Integer.parseInt(parts[0]), Integer.parseInt(parts[1]) };
            }
        } catch (Exception ignored) {}
        return new int[]{ 24, 80 };
    }

    // -------------------------------------------------------------------------
    // Sync API
    // -------------------------------------------------------------------------

    /**
     * Call once before the first draw().
     * Shrinks the scroll region to exclude the last line, reserving it for the bar.
     */
    public static void init() {
        int rows = termSize()[0];
        // CSR: rows 1..(rows-1) are the scroll region (1-based); last row is reserved
        ttyWrite("\033[1;" + (rows - 1) + "r"   // set scroll region
               + "\033[" + (rows - 1) + ";1H"); // park cursor at bottom of scroll region
    }

    /** Render the bar without a label. */
    public static void draw(int current, int total) {
        draw(current, total, null);
    }

    /**
     * Render the bar on the last terminal line.
     * Safe to call while other output scrolls above it.
     *
     * @param current  current step (0..total)
     * @param total    total number of steps
     * @param label    optional label (max 20 chars shown); null or empty = no label
     */
    public static void draw(int current, int total, String label) {
        int[] size  = termSize();
        int rows    = size[0];
        int cols    = size[1];
        boolean hasLabel = label != null && !label.isEmpty();

        // Overhead: "[" + bar + "] NNN% S" = 9 chars; with label prefix adds 21 more
        int overhead = hasLabel ? 30 : 9;
        int width    = Math.max(1, cols - overhead);

        int percent = total > 0 ? current * 100 / total : 0;
        int filled  = total > 0 ? current * width / total : 0;
        int empty   = width - filled;

        String color    = pickColor(percent, colorMode, colorCode);
        String filledBar = "█".repeat(filled);
        String emptyBar  = "░".repeat(empty);
        String bar = color.isEmpty()
                ? filledBar + emptyBar
                : color + filledBar + RESET + emptyBar;

        String spinner = spinFrames[spinIdx];
        spinIdx = (spinIdx + 1) % spinFrames.length;

        String line = hasLabel
                ? String.format("%-20s [%s] %3d%% %s", label, bar, percent, spinner)
                : String.format("[%s] %3d%% %s", bar, percent, spinner);

        // ESC-7 / ESC-8: save / restore cursor (DEC private sequences, widely supported)
        ttyWrite("\0337"                        // save cursor
               + "\033[" + rows + ";1H"        // jump to reserved last line
               + "\033[2K"                     // clear line
               + line
               + "\0338");                     // restore cursor
    }

    /**
     * Call once after the last draw().
     * Restores the full scroll region and clears the reserved line.
     */
    public static void done() {
        int rows = termSize()[0];
        ttyWrite("\033[1;" + rows + "r"        // restore full scroll region
               + "\033[" + rows + ";1H"       // move to reserved line
               + "\033[2K"                    // clear it
               + "\033[" + (rows - 1) + ";1H" // park cursor above
               + "\n");                        // ensure fresh line
    }

    // -------------------------------------------------------------------------
    // Async API
    // -------------------------------------------------------------------------

    /** Start the async bar with no label (~20 fps renderer thread). */
    public static void start(int total) {
        start(total, null);
    }

    /**
     * Start the async bar. The renderer runs in a daemon thread at ~20 fps.
     * Call update() to advance progress and log() to print lines safely.
     */
    public static void start(int total, String label) {
        asyncCurrent = 0;
        asyncRunning = true;
        logQueue.clear();

        // Snapshot configuration for the renderer thread
        final String[]    frames = spinFrames.clone();
        final ColorMode   cm     = colorMode;
        final String      cc     = colorCode;

        init();

        asyncThread = new Thread(() -> {
            int idx = 0;
            while (asyncRunning) {
                // Flush pending log lines before drawing the bar
                String msg;
                while ((msg = logQueue.poll()) != null) {
                    ttyWrite(msg + "\n");
                }

                int[] size  = termSize();
                int rows    = size[0];
                int cols    = size[1];
                boolean hasLabel = label != null && !label.isEmpty();
                int overhead = hasLabel ? 30 : 9;
                int width    = Math.max(1, cols - overhead);

                int cur  = asyncCurrent;
                int pct  = total > 0 ? cur * 100 / total : 0;
                int fil  = total > 0 ? cur * width / total : 0;

                String color    = pickColor(pct, cm, cc);
                String filledBar = "█".repeat(fil);
                String emptyBar  = "░".repeat(width - fil);
                String bar = color.isEmpty()
                        ? filledBar + emptyBar
                        : color + filledBar + RESET + emptyBar;

                String spinner = frames[idx];
                idx = (idx + 1) % frames.length;

                String line = hasLabel
                        ? String.format("%-20s [%s] %3d%% %s", label, bar, pct, spinner)
                        : String.format("[%s] %3d%% %s", bar, pct, spinner);

                ttyWrite("\0337\033[" + rows + ";1H\033[2K" + line + "\0338");

                try { Thread.sleep(50); } catch (InterruptedException e) { break; }
            }
        });
        asyncThread.setDaemon(true);
        asyncThread.start();
    }

    /** Report current progress from any thread. */
    public static void update(int current) {
        asyncCurrent = current;
    }

    /**
     * Thread-safe println.
     * In async mode: queues the message so the renderer prints it without interleaving.
     * In sync mode: behaves like System.out.println.
     */
    public static void log(String message) {
        if (asyncRunning) {
            logQueue.offer(message);
        } else {
            System.out.println(message);
        }
    }

    /** Stop the async bar and restore the terminal. */
    public static void stop() {
        asyncRunning = false;
        if (asyncThread != null) {
            try { asyncThread.join(500); } catch (InterruptedException ignored) {}
            asyncThread = null;
        }
        // Drain any log messages that arrived after the renderer's last tick
        String msg;
        while ((msg = logQueue.poll()) != null) {
            System.out.println(msg);
        }
        done();
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    private static String pickColor(int percent, ColorMode cm, String cc) {
        if (cm == ColorMode.AUTO) {
            if (percent >= 66) return C_GRN;
            if (percent >= 33) return C_YEL;
            return C_RED;
        }
        return cm == ColorMode.NONE ? "" : cc;
    }

    private static void ttyWrite(String s) {
        try {
            TTY.write(s.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            TTY.flush();
        } catch (IOException ignored) {}
    }

    // -------------------------------------------------------------------------
    // Demo
    // -------------------------------------------------------------------------

    public static void main(String[] args) throws InterruptedException {
        demoSimple();
        demoLabeled();
        demoAsync();
    }

    private static void demoSimple() throws InterruptedException {
        int total = 50;
        init();
        System.out.println("Simple progress bar (other output won't disturb it):");
        for (int i = 0; i <= total; i++) {
            draw(i, total);
            Thread.sleep(50);
        }
        done();
    }

    private static void demoLabeled() throws InterruptedException {
        String[] steps = {"Downloading", "Extracting", "Installing", "Configuring"};
        int total = 30;
        init();
        System.out.println("Labeled progress bars:");
        for (String label : steps) {
            System.out.println("  Starting: " + label);
            for (int i = 0; i <= total; i++) {
                draw(i, total, label);
                Thread.sleep(30);
            }
            System.out.println("  Done:     " + label);
        }
        done();
    }

    private static void demoAsync() throws InterruptedException {
        int total = 20;
        start(total, "Computing");
        log("Async: bar animates while work runs at variable speed:");
        for (int i = 0; i <= total; i++) {
            Thread.sleep(50 + (int)(Math.random() * 100)); // 50-150 ms of "work"
            update(i);
            log("  Step " + i + " done");
        }
        stop();
    }
}
