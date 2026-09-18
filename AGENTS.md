# Antigravity Workspace Guidelines & Performance Rules

This document sets mandatory guidelines for all Antigravity agent sessions operating in this repository (`trufold_studio`). These rules are always active to maximize response speed, minimize token overhead, and ensure consistent code modifications.

---

## 1. Code Navigation & Search Optimization (High Speed)

- **Always use `git grep -n`**:
  - For finding identifiers, methods, classes, and strings, use `git grep -n "<pattern>"` via `run_command`.
  - It runs in milliseconds on this codebase, completely bypassing slow directory traversals.
  - Do NOT use broad, unstructured file searches or full directory traversals.

- **Targeted File Viewing (No Full-File Dumps)**:
  - This codebase contains large files (e.g. `unfolded_canvas_widget.dart` is >8,000 lines).
  - **Never read large files in full**. Always use `git grep -n` to pinpoint exact line numbers first.
  - Then use `view_file` with explicit `StartLine` and `EndLine` slices (maximum 30–60 lines around the target).

- **Inspect Changes via Git**:
  - Always use `git diff` or `git status -s` to inspect your modifications instead of re-reading modified files into context.

- **Ignore Generated & Ephemeral Directories**:
  - Never search inside: `build/`, `.dart_tool/`, `ios/Pods/`, `android/.gradle/`, `windows/flutter/ephemeral/`.

---

## 2. Code Editing Rules

- **Surgical, Targeted Edits**:
  - Use `replace_file_content` for single contiguous changes and `multi_replace_file_content` for non-contiguous changes.
  - Keep replacement chunks as compact as possible. Do NOT replace entire classes or large blocks of unchanged code.
  - Double-check exact indentation and line boundaries before applying edits.

- **Documentation & Comment Integrity**:
  - Preserve all existing comments, docstrings, and architectural notes unless explicitly asked to modify them.

---

## 3. Fast Verification & Testing

- **Targeted Analyzer**:
  - After modifying a file, run `flutter analyze <modified_file>` (takes ~3–5 seconds) rather than analyzing the whole workspace.

- **Targeted Unit / Widget Tests**:
  - Run the specific test file associated with your changes:
    `flutter test test/modules/sheet_metal_studio/<test_name>.dart`
  - Avoid running the full test suite for minor changes unless performing a full regression check.

---

## 4. Key Architecture Map

- **Canvas & Painter Widgets**: `lib/sheet_metal_studio/views/widgets/unfolded_canvas_widget.dart`, `canvas_3d_widget.dart`
- **State & ViewModels**: `lib/sheet_metal_studio/viewmodels/sheet_metal_studio_viewmodel.dart`
- **CAD Primitives & Models**: `lib/sheet_metal_studio/models/cad_primitives.dart`, `cad_geometry.dart`, `cad_dimension.dart`, `cad_constraint.dart`
- **Solvers & Engines**: `lib/sheet_metal_studio/engine/`
- **Module Tests**: `test/modules/sheet_metal_studio/`
