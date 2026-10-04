# Finder result reveal verification

- Direct and Store Release builds passed, and the architecture check found 15 bundled Mach-O files with both arm64 and x86_64 slices.
- The Swift package suite passed: 578 tests in 138 suites, including the new preference test.
- In a disposable ad hoc signed app, the new Extensions checkbox appeared enabled by default (settings-before.png). I disabled it (settings-after.png).
- With it off, `Extract Here` unpacked disposable `sample.zip` to `hello.txt` in the test folder and no Finder result window appeared. The existing Finder windows were Downloads and tmp.
- With it on, a second disposable `sample2.zip` unpacked to `hello2.txt` and a new Finder window named `manual` appeared; finder-result-on.png shows only the disposable test files. I closed that window and switched the option back off.
- The test used a sandbox grant for the disposable `/private/tmp/mp-finder-reveal/manual` folder. The extension appears disabled in the screenshots because the app was run from a disposable review copy; the PR does not change extension activation.
- All screenshots were captured without the mouse cursor.
