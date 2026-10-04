// `Progress` for `ProgressView(_ progress:)`: wasm has no Foundation `Progress`, so the thin
// module names SwiftUIWebCore's observable object `Progress` there; Apple platforms keep
// Foundation's, which the progress view polls every frame (no key-value observing here).
#if os(WASI)
public typealias Progress = _WebProgress
#else
import Foundation

extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    /// A progress view following a Foundation `Progress`, read every frame (approximate: no
    /// key-value observing).
    public init(_ progress: Progress) {
        self.init(_polling: { progress.isIndeterminate ? nil : min(max(progress.fractionCompleted, 0), 1) },
                  description: progress.localizedDescription)
    }
}
#endif
