// The keyboard notifications as the Countries app's SystemEventsHandler consumes them
// (uk-app-delegate-adaptor): keyboardWillShow/keyboardWillHide from NotificationCenter, the
// end frame's height out of keyboardFrameEndUserInfoKey, published into app state.
import Combine
import Foundation
import SwiftUI
import UIKit

final class KeyboardCheck: ObservableObject {
    @Published var height: CGFloat = 0
    private var subscriptions = Set<AnyCancellable>()

    init() {
        let center = NotificationCenter.default
        let willShow = center.publisher(for: UIApplication.keyboardWillShowNotification).map { $0.keyboardHeight }
        let willHide = center.publisher(for: UIApplication.keyboardWillHideNotification).map { _ in CGFloat(0) }
        willShow.merge(with: willHide).receive(on: DispatchQueue.main).sink { [weak self] in self?.height = $0 }.store(in: &subscriptions)
    }

    var summary: String { "keyboard: \(Int(height))" }
}

private extension Notification {
    var keyboardHeight: CGFloat {
        (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height ?? 0
    }
}
