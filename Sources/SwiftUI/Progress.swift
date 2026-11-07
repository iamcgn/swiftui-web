// `Progress` for `ProgressView(_ progress:)`: wasm's is WebFoundation's observable `Progress`,
// which the progress view follows; Apple platforms keep Foundation's, which the progress view
// polls every frame (no key-value observing here).
#if !os(WASI)
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
