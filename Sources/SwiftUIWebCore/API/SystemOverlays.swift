// The system's overlays above an app: the status bar and the home indicator. A page has neither
// (UIKitWeb's status bar manager answers for the strip above the safe area), so a view that
// hides them lays out and draws as it would with them shown; the modifiers are here so apps that
// ask for it (SwiftUIExperiments' keys hides the status bar) build unchanged.

extension View {
    /// Sets the visibility of the status bar: nothing to hide on a page.
    nonisolated public func statusBarHidden(_ hidden: Bool = true) -> some View { self }

    /// Sets the preferred visibility of the system's overlays (the home indicator, and on
    /// visionOS the window controls): nothing to hide on a page.
    nonisolated public func persistentSystemOverlays(_ visibility: Visibility) -> some View { self }

    /// Sets the visibility of the status bar: `statusBarHidden(_:)` with its older name.
    @available(*, deprecated, renamed: "statusBarHidden(_:)")
    nonisolated public func statusBar(hidden: Bool) -> some View { statusBarHidden(hidden) }
}
