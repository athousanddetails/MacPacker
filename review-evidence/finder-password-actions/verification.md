# Finder password actions — verification

- `swift test --package-path Modules`: **579 tests in 138 suites passed**.
- Release `xcodebuild` completed for `MacPacker` and `MacPacker Store`.
- `scripts/check-architectures.sh`: **15 Mach-O files checked**, each with `arm64` and `x86_64` slices.
- Manually enabled each Finder action in the disposable test app and opened its dialog through the app URL. The password prompt requires matching nonempty fields; Cancel creates nothing. The generated-password dialog requires **Copy Password & Compress** before writing.
- Created an archive with each action. `7zz t` succeeded with its password and failed with a wrong password. Opening the generated archive without its password did not reveal file names. No password was present in the Finder app URL.
- The screenshots show the pre-existing Extensions panel, the new off-by-default settings, and both new dialogs. They were captured without the mouse cursor.
