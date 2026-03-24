# Regenerate with: vhs demo.tape
Output demo.gif

Set Shell   "bash"
Set FontSize 14
Set Width   900
Set Height  440
Set Theme   "Dracula"
Set Padding 20

# Give the shell a moment to settle before typing
Sleep 500ms

# --- Demo 1: simple unlabeled bar ---
Type "source progress_bar.sh && demo_simple"
Enter
# 51 iterations × 0.05 s each ≈ 2.6 s
Sleep 4s

# blank line between demos
Enter

# --- Demo 2: labeled multi-phase bar ---
Type "demo_labeled"
Enter
# 4 phases × 31 iterations × 0.03 s each ≈ 3.7 s
Sleep 6s

# blank line between demos
Enter

# --- Demo 3: async bar — bar animates while work runs at variable speed ---
Type "demo_async"
Enter
# 21 iterations × avg ~0.4 s each ≈ 8 s; add headroom for variance
Sleep 12s
