// Translation's SwiftUI modifiers (on Apple's platforms they come with the `_Translation_SwiftUI`
// overlay): `translationTask` hands the app a session that may download models whenever its
// configuration appears or changes, and `translationPresentation` shows a text's translation in
// a popover, with Copy and, when the app offers one, Replace with Translation.
#if os(WASI)
import WebFoundation
import WebFoundationFormats
#else
import Foundation
#endif
import SwiftUI

extension View {
    /// Runs `action` with a session for `configuration` when the view appears and whenever the
    /// configuration changes or is invalidated; nil runs nothing.
    nonisolated public func translationTask(_ configuration: TranslationSession.Configuration?,
                                            action: @escaping @MainActor @Sendable (TranslationSession) async -> Void) -> some View {
        task(id: configuration) {
            guard let configuration else { return }
            await action(TranslationSession(configuration: configuration))
        }
    }

    /// Runs `action` with a session from `source` (nil: detected) to `target` (nil: the person's
    /// preferred language) when the view appears.
    nonisolated public func translationTask(source: Locale.Language? = nil, target: Locale.Language? = nil,
                                            action: @escaping @MainActor @Sendable (TranslationSession) async -> Void) -> some View {
        translationTask(TranslationSession.Configuration(source: source, target: target), action: action)
    }

    /// Shows `text` translated to the person's preferred language in a popover while
    /// `isPresented` is true. With `replacementAction`, a button hands the translation back.
    public func translationPresentation(isPresented: Binding<Bool>, text: String,
                                        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
                                        arrowEdge: Edge = .top,
                                        replacementAction: (@MainActor @Sendable (String) -> Void)? = nil) -> some View {
        popover(isPresented: isPresented, attachmentAnchor: attachmentAnchor, arrowEdge: arrowEdge) {
            _TranslationCard(text: text, isPresented: isPresented, replacementAction: replacementAction)
        }
    }
}

/// The translation popover: the text, its translation (or why there is none) and the actions.
struct _TranslationCard: View {
    let text: String
    let isPresented: Binding<Bool>
    let replacementAction: (@MainActor @Sendable (String) -> Void)?
    @State private var translation: String?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .foregroundStyle(.secondary)
            Divider()
            if let translation {
                Text(translation)
                HStack {
                    Button("Copy Translation") { UIPasteboard.general.string = translation }
                    if let replacementAction {
                        Spacer()
                        Button("Replace with Translation") {
                            replacementAction(translation)
                            isPresented.wrappedValue = false
                        }
                    }
                }
            } else if let failure {
                Text(failure)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .padding(16)
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360, alignment: .leading)
        .translationTask { session in
            do {
                translation = try await session.translate(text).targetText
            } catch {
                failure = "Translation isn't available for this text."
            }
        }
    }
}
