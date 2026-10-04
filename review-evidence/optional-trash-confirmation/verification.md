# Optional Trash confirmation — verification

- Focused test passed: default-on confirmation can be explicitly disabled and re-enabled.
- Full Swift package suite: **611 tests in 145 suites passed**.
- Direct and Store Release builds succeeded. All **16 bundled Mach-O files** have `arm64` and `x86_64` slices.
- In a disposable signed app, enabled “Move archives to Trash after successful extraction” and disabled its new “Ask before moving archives to Trash” sub-option. A disposable ZIP extracted successfully, its source archive was moved to Trash, and no second confirmation appeared. The initial sandbox folder-access picker appeared and was granted for the test directory.
- The before/after General settings screenshots were captured without the mouse cursor.
