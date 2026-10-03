# Browser and Computer visual evidence

These are native Flutter raster captures from
`test/shared/pages/webview/browser_computer_visual_test.dart`, using the app's
`AppThemeBuilder`, default palette, Android layout, and real Roboto/Lucide fonts.
Portrait fixtures are 390 × 844 logical pixels, captured at 2× (780 × 1688 PNGs).
The Glass variant turns on `SettingsProvider.glassTheme`; its chat fixture uses
the app's static `ChatGradientBackground`. At baseline, browser chrome and the
old activity sheet did not change with that setting, so those before images are
identical.

The embedded WebView is the existing test-only `FakeWebViewPlatform`, which
renders a blank area. These images show the app UI around it; they do not prove
Android WebView page rendering, native screenshots, touch forwarding, or phone
performance. The example URL is `https://example.com`; no network page is loaded.
The composer background and message field are a small deterministic fixture
hosting the real `ComposerStatusStrip`, rather than a complete saved chat.

Before captures were made on 2026-10-02 with the browser and composer product
files unchanged from `24766f97c81ca26f5b1200767e4ba8874883cab1`, before the browser
polish and Computer integration edits. Baseline capture ran six scoped widget
tests successfully. The original `sheet` images show the browser activity log:
the Computer sheet did not exist at baseline.

| Surface | Dark before | Glass before |
| --- | --- | --- |
| Fullscreen browser | [PNG](before-dark-browser.png) | [PNG](before-glass-browser.png) |
| Overflow menu | [PNG](before-dark-menu.png) | [PNG](before-glass-menu.png) |
| Composer strip, command and plan | [PNG](before-dark-strip.png) | [PNG](before-glass-strip.png) |
| Previous activity sheet | [PNG](before-dark-sheet.png) | [PNG](before-glass-sheet.png) |

| Surface | Dark after | Glass after |
| --- | --- | --- |
| Fullscreen browser | [PNG](after-dark-browser.png) | [PNG](after-glass-browser.png) |
| Grouped overflow menu | [PNG](after-dark-menu.png) | [PNG](after-glass-menu.png) |
| Computer composer strip and plan | [PNG](after-dark-strip.png) | [PNG](after-glass-strip.png) |
| Computer sheet, running command | [PNG](after-dark-sheet.png) | [PNG](after-glass-sheet.png) |
| Computer sheet, browser step | [PNG](after-dark-sheet-browser.png) | [PNG](after-glass-sheet-browser.png) |
| Computer sheet, file step | [PNG](after-dark-sheet-file.png) | [PNG](after-glass-sheet-file.png) |
| Existing browser activity sheet | [PNG](after-dark-activity-sheet.png) | [PNG](after-glass-activity-sheet.png) |

The Computer fixture has three steps: a running shared test command, an
`observe` browser call, and reading `/workspace/README.md`. The browser step has
no screenshot cache entry, so its thumbnail deliberately exercises the icon
fallback. The small output and file contents are synthetic fixtures; the PNGs
are captures of the real widgets displaying those fixtures.

| Regression scenario | Dark after | Glass after |
| --- | --- | --- |
| Browser, keyboard and 1.3 scale | [PNG](after-dark-browser-keyboard-130.png) | [PNG](after-glass-browser-keyboard-130.png) |
| Browser, landscape and 1.3 scale | [PNG](after-dark-browser-landscape-130.png) | [PNG](after-glass-browser-landscape-130.png) |
| Computer, keyboard and 1.3 scale | [PNG](after-dark-sheet-keyboard-130.png) | [PNG](after-glass-sheet-keyboard-130.png) |
| Computer, landscape and 1.3 scale | [PNG](after-dark-sheet-landscape-130.png) | [PNG](after-glass-sheet-landscape-130.png) |

Reproduce the capture using Flutter 3.44.9 / Dart 3.12.2. `COMPUTER_QA_FONT`
selects a local Roboto font; the bundled JetBrains Mono font is used when the
variable is absent, which changes text metrics. The command below uses the
toolchain's Roboto-Regular.ttf used for these artifacts:

```bash
source "$HOME/.moru-toolchains/activate.sh"
COMPUTER_QA_FONT="$HOME/.moru-toolchains/flutter-3.44.9/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf" \
  flutter test --no-pub --reporter expanded \
  test/shared/pages/webview/browser_computer_visual_test.dart \
  --dart-define=COMPUTER_QA_DIR="$PWD/docs/design/browser" \
  --dart-define=COMPUTER_QA_PHASE=after
```

The `before` phase is for the original source revision; running it on changed
product code would overwrite the historical evidence with changed UI. Keep the
committed baseline PNGs intact. The final harness imports the new Computer
widgets, so the original pre-change harness is needed to regenerate the
historical baseline on the original product source.

After captures also exercise 1.3 text scaling with a simulated 300 dp keyboard
inset and Android landscape (844 × 390 dp). Those are fixture checks for overflow
and sheet navigation, not device tests. Ordinary scoped test runs build the same fixtures
and assert their visible controls without writing images. To compare the exact
native PNGs with their saved goldens, use the same font and toolchain:

```bash
COMPUTER_QA_FONT="$HOME/.moru-toolchains/flutter-3.44.9/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf" \
  flutter test --no-pub --reporter expanded \
  test/shared/pages/webview/browser_computer_visual_test.dart \
  --dart-define=COMPUTER_QA_COMPARE=true
```

Golden comparison reads the saved `after-*.png` files and never overwrites them.
Verified on 2026-10-02: all 16 capture fixtures and all 16 final golden
comparisons passed. A standard scoped run using the bundled fallback font also
passed all 16 fixtures. The visual harness passed `dart analyze --fatal-infos`.
The harness waits for finite sheet/entry animations to finish and checks that
the Computer controls are inside the available viewport before capturing. This
avoids accepting a hidden panel simply because its text exists in the tree.
Capture runs use `tester.runAsync` around
`RenderRepaintBoundary.toImage` and PNG encoding; no image generation, image
editing, native device screenshots, or full repository test suite was used.
