---
name: fast-code-navigation
description: >-
  Provides rapid, git-accelerated code search, navigation, and targeted file editing guidelines
  for the trufold_studio codebase. Trigger whenever locating symbols, editing large widgets,
  or optimizing tool execution time.
---

# Fast Code Navigation & Editing Guidelines for trufold_studio

Use these procedures whenever navigating or modifying code in this repository:

1. **Fast Symbol & Identifier Search**:
   - Use `git grep -n "<pattern>"` via `run_command`.
   - Never use slow directory walkers or broad ripgrep searches.

2. **Targeted File Inspection**:
   - For large files (e.g. `unfolded_canvas_widget.dart` >8000 lines), always identify line numbers with `git grep -n` first.
   - Use `view_file` with precise `StartLine` and `EndLine` slices (20–50 lines).

3. **Compact Modifications**:
   - Use `replace_file_content` for single contiguous edits and `multi_replace_file_content` for non-contiguous edits.
   - Avoid replacing large sections of code. Keep target chunks compact.

4. **Fast Validation**:
   - Run `flutter analyze <modified_file>` immediately after edits.
   - Run only the corresponding test file (`flutter test test/modules/...`).
