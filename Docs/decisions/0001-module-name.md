# 0001. The app-facing module is named `SwiftUI`

Date: 2026-09-01
Status: accepted

## Context
Unmodified app source says `import SwiftUI`. On wasm/Linux no system module of that name exists.
On macOS the system framework has the same name; SwiftPM `moduleAliases` ignore platform
conditions (swift-package-manager#7412) and `#if os()` in manifests evaluates on the host.

## Decision
A thin target named `SwiftUI` re-exports `SwiftUIWebCore`. Tests import `SwiftUI`; if the
spike shows the system framework wins on macOS, tests import `SwiftUIWebCore` directly.
The golden harness is a separate package with no dependency on this one, so `import SwiftUI`
there always means Apple's framework.

## Evidence
Spike 0.3, 2026-09-01, macOS 26.2 with the swiftly Swift 6.3.3 toolchain (Command Line Tools only):
`swift test` on the root package compiled `import SwiftUI` in the test targets against
`.build/arm64-apple-macosx/debug/Modules/SwiftUI.swiftmodule` (ours), and
`SwiftUIWebMarker.implementation == "SwiftUIWeb"` passed. Explicit `-I` build-directory paths are
searched before SDK frameworks, so the package's own `SwiftUI` module shadows Apple's.
The `SwiftUIWebCore` fallback import stays available but has not been needed.

Also observed: the golden harness in `Harness/` (Apple 6.2.3 toolchain) links Apple's SwiftUI
and generated `Fixtures/Goldens/text/hello` from a fixture source that both packages compile.
