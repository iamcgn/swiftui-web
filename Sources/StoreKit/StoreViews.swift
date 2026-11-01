// StoreKit's SwiftUI views and modifiers: product and store views, the subscription store, the
// review prompt action, entitlement tasks and the App Store sheets. With no products on the web,
// a product view shows its product as unavailable (a custom `ProductViewStyle` gets that state),
// a store lists its products that way, the subscription store shows its marketing content over
// a note that subscriptions are unavailable, and the sheets close as soon as they open.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

// MARK: - Review prompt

/// Asks for an App Store rating. The web has no rating prompt, so calling it shows nothing.
public struct RequestReviewAction: Sendable {
    nonisolated init() {}
    @MainActor public func callAsFunction() {}
}

private struct RequestReviewKey: EnvironmentKey {
    static let defaultValue = RequestReviewAction()
}

extension EnvironmentValues {
    /// The action that asks for an App Store rating.
    public var requestReview: RequestReviewAction { self[RequestReviewKey.self] }
}

// MARK: - Entitlement tasks

/// The state of a task that loads the customer's entitlements.
public enum EntitlementTaskState<State> {
    case loading
    case failure(any Error)
    case success(State)

    /// The loaded value, or nil while loading or after a failure.
    public var value: State? {
        if case .success(let value) = self { return value }
        return nil
    }

    /// The state with its loaded value transformed; a thrown error becomes a failure.
    public func map<T>(_ transform: (State) async throws -> T) async -> EntitlementTaskState<T> {
        switch self {
        case .loading: return .loading
        case .failure(let error): return .failure(error)
        case .success(let value):
            do { return .success(try await transform(value)) } catch { return .failure(error) }
        }
    }
}

extension EntitlementTaskState: Sendable where State: Sendable {}

// MARK: - Product views

/// The properties of a product view, for a custom `ProductViewStyle`.
public struct ProductViewStyleConfiguration {
    /// The product's icon.
    public struct Icon: View {
        package let content: AnyView
        package init(_ content: AnyView) { self.content = content }
        public var body: some View { content }
    }

    public let productID: Product.ID
    /// The product, once loaded; on the web it never loads.
    public let product: Product?
    public let state: Product.TaskState
    public let hasCurrentEntitlement: Bool
    public let icon: Icon

    /// Starts buying the product. There is no product to buy on the web, so nothing happens.
    public func purchase() {}
    public func purchase(options: Set<Product.PurchaseOption>) {}
}

/// A type that sets the look of the product views in a view hierarchy.
@MainActor @preconcurrency
public protocol ProductViewStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ProductViewStyleConfiguration
}

extension ProductViewStyle {
    @MainActor
    func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

private struct ProductViewStyleKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (any ProductViewStyle)? = nil
}

extension EnvironmentValues {
    var _productViewStyle: (any ProductViewStyle)? {
        get { self[ProductViewStyleKey.self] }
        set { self[ProductViewStyleKey.self] = newValue }
    }
}

/// The standard product view: the icon beside the product's name, description and price, or
/// the product's state while it isn't there.
struct _StandardProductBody: View {
    enum Size { case compact, regular, large }
    let configuration: ProductViewStyleConfiguration
    let size: Size

    var body: some View {
        if size == .large {
            VStack(spacing: 8) {
                configuration.icon
                details
            }
        } else {
            HStack(spacing: size == .compact ? 8 : 12) {
                configuration.icon
                details
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private var details: some View {
        if let product = configuration.product {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName).font(.headline)
                if size != .compact, !product.description.isEmpty {
                    Text(product.description).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(product.displayPrice).font(.subheadline)
            }
        } else if case .loading = configuration.state {
            ProgressView()
        } else {
            Text("Unavailable").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// The default product view style, based on where the view is.
public struct AutomaticProductViewStyle {
    @preconcurrency nonisolated public init() {}
}
extension AutomaticProductViewStyle: ProductViewStyle {
    public func makeBody(configuration: Configuration) -> some View { _StandardProductBody(configuration: configuration, size: .regular) }
}

/// A compact product view style.
public struct CompactProductViewStyle {
    @preconcurrency nonisolated public init() {}
}
extension CompactProductViewStyle: ProductViewStyle {
    public func makeBody(configuration: Configuration) -> some View { _StandardProductBody(configuration: configuration, size: .compact) }
}

/// The regular product view style.
public struct RegularProductViewStyle {
    @preconcurrency nonisolated public init() {}
}
extension RegularProductViewStyle: ProductViewStyle {
    public func makeBody(configuration: Configuration) -> some View { _StandardProductBody(configuration: configuration, size: .regular) }
}

/// A large product view style, the icon above the details.
public struct LargeProductViewStyle {
    @preconcurrency nonisolated public init() {}
}
extension LargeProductViewStyle: ProductViewStyle {
    public func makeBody(configuration: Configuration) -> some View { _StandardProductBody(configuration: configuration, size: .large) }
}

extension ProductViewStyle where Self == AutomaticProductViewStyle {
    public static var automatic: AutomaticProductViewStyle { AutomaticProductViewStyle() }
}
extension ProductViewStyle where Self == CompactProductViewStyle {
    public static var compact: CompactProductViewStyle { CompactProductViewStyle() }
}
extension ProductViewStyle where Self == RegularProductViewStyle {
    public static var regular: RegularProductViewStyle { RegularProductViewStyle() }
}
extension ProductViewStyle where Self == LargeProductViewStyle {
    public static var large: LargeProductViewStyle { LargeProductViewStyle() }
}

/// Shows a product's style from the environment, or the automatic style.
struct _ProductViewBody: View {
    @Environment(\._productViewStyle) private var style
    let configuration: ProductViewStyleConfiguration

    var body: some View {
        if let style {
            style.makeBodyErased(configuration)
        } else {
            _StandardProductBody(configuration: configuration, size: .regular)
        }
    }
}

/// A view that shows a product and lets the customer buy it. On the web the product doesn't
/// load, so the view shows it as unavailable with its placeholder icon.
public struct ProductView<Icon: View, PlaceholderIcon: View>: View {
    private let configuration: ProductViewStyleConfiguration

    private init(id: Product.ID, product: Product?, icon: AnyView) {
        configuration = ProductViewStyleConfiguration(
            productID: id, product: product, state: product.map { .success($0) } ?? .unavailable,
            hasCurrentEntitlement: false, icon: ProductViewStyleConfiguration.Icon(icon))
    }

    public init(id productID: Product.ID, prefersPromotionalIcon: Bool = false,
                @ViewBuilder icon: () -> Icon, @ViewBuilder placeholderIcon: () -> PlaceholderIcon) {
        self.init(id: productID, product: nil, icon: AnyView(placeholderIcon()))
    }

    public init(_ product: Product, prefersPromotionalIcon: Bool = false, @ViewBuilder icon: () -> Icon) where PlaceholderIcon == EmptyView {
        self.init(id: product.id, product: product, icon: AnyView(icon()))
    }

    public var body: some View { _ProductViewBody(configuration: configuration) }
}

extension ProductView where PlaceholderIcon == EmptyView {
    public init(id productID: Product.ID, prefersPromotionalIcon: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.init(id: productID, product: nil, icon: AnyView(EmptyView()))
    }
}

extension ProductView where Icon == EmptyView, PlaceholderIcon == EmptyView {
    public init(id productID: Product.ID, prefersPromotionalIcon: Bool = false) {
        self.init(id: productID, product: nil, icon: AnyView(EmptyView()))
    }

    public init(_ product: Product, prefersPromotionalIcon: Bool = false) {
        self.init(id: product.id, product: product, icon: AnyView(EmptyView()))
    }
}

extension View {
    /// Sets the style of the product views in this view.
    nonisolated public func productViewStyle<S: ProductViewStyle>(_ style: S) -> some View {
        environment(\._productViewStyle, style)
    }
}

// MARK: - Store views

/// A store of products. On the web none load, so each shows as unavailable.
public struct StoreView<Icon: View, PlaceholderIcon: View>: View {
    private struct Item: Identifiable {
        let id: Product.ID
        let product: Product?
    }
    private let items: [Item]
    private let icon: (Product) -> Icon
    private let placeholderIcon: PlaceholderIcon

    public init(ids: some Collection<Product.ID>, prefersPromotionalIcon: Bool = false,
                @ViewBuilder icon: @escaping (Product) -> Icon, @ViewBuilder placeholderIcon: () -> PlaceholderIcon) {
        items = ids.map { Item(id: $0, product: nil) }
        self.icon = icon
        self.placeholderIcon = placeholderIcon()
    }

    public init(products: some Collection<Product>, prefersPromotionalIcon: Bool = false,
                @ViewBuilder icon: @escaping (Product) -> Icon, @ViewBuilder placeholderIcon: () -> PlaceholderIcon) {
        items = products.map { Item(id: $0.id, product: $0) }
        self.icon = icon
        self.placeholderIcon = placeholderIcon()
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(items) { item in
                    if let product = item.product {
                        ProductView(product) { icon(product) }
                    } else {
                        ProductView(id: item.id, icon: { EmptyView() }, placeholderIcon: { placeholderIcon })
                    }
                }
            }
            .padding()
        }
    }
}

extension StoreView where PlaceholderIcon == EmptyView {
    public init(ids: some Collection<Product.ID>, prefersPromotionalIcon: Bool = false, @ViewBuilder icon: @escaping (Product) -> Icon) {
        self.init(ids: ids, prefersPromotionalIcon: prefersPromotionalIcon, icon: icon, placeholderIcon: { EmptyView() })
    }

    public init(products: some Collection<Product>, prefersPromotionalIcon: Bool = false, @ViewBuilder icon: @escaping (Product) -> Icon) {
        self.init(products: products, prefersPromotionalIcon: prefersPromotionalIcon, icon: icon, placeholderIcon: { EmptyView() })
    }
}

extension StoreView where Icon == EmptyView, PlaceholderIcon == EmptyView {
    public init(ids: some Collection<Product.ID>) {
        self.init(ids: ids, icon: { _ in EmptyView() }, placeholderIcon: { EmptyView() })
    }

    public init(products: some Collection<Product>) {
        self.init(products: products, icon: { _ in EmptyView() }, placeholderIcon: { EmptyView() })
    }
}

/// A store of a subscription group's plans. On the web no plan loads, so the view shows its
/// marketing content over a note that subscriptions are unavailable.
public struct SubscriptionStoreView<Content: View>: View {
    private let content: Content

    public init(groupID: String, visibleRelationships: Product.SubscriptionRelationship = .all, @ViewBuilder marketingContent: () -> Content) {
        content = marketingContent()
    }

    public init(productIDs: some Collection<Product.ID>, @ViewBuilder marketingContent: () -> Content) {
        content = marketingContent()
    }

    public init(subscriptions: some Collection<Product>, @ViewBuilder marketingContent: () -> Content) {
        content = marketingContent()
    }

    public var body: some View {
        VStack(spacing: 16) {
            content
            Text("Subscriptions unavailable").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
    }
}

extension SubscriptionStoreView where Content == EmptyView {
    public init(groupID: String, visibleRelationships: Product.SubscriptionRelationship = .all) {
        self.init(groupID: groupID, visibleRelationships: visibleRelationships) { EmptyView() }
    }

    public init(productIDs: some Collection<Product.ID>) {
        self.init(productIDs: productIDs) { EmptyView() }
    }

    public init(subscriptions: some Collection<Product>) {
        self.init(subscriptions: subscriptions) { EmptyView() }
    }
}

extension ContainerBackgroundPlacement {
    /// The background of a subscription store view.
    public static let subscriptionStore = ContainerBackgroundPlacement("subscriptionStore")
    /// The background of a subscription store's header.
    public static let subscriptionStoreHeader = ContainerBackgroundPlacement("subscriptionStoreHeader")
    /// The background of a subscription store, its full height.
    public static let subscriptionStoreFullHeight = ContainerBackgroundPlacement("subscriptionStoreFullHeight")
}

/// A kind of button a store view shows.
public struct StoreButtonKind: Hashable, Sendable {
    package let name: String
    public static let cancellation = StoreButtonKind(name: "cancellation")
    public static let restorePurchases = StoreButtonKind(name: "restorePurchases")
    public static let redeemCode = StoreButtonKind(name: "redeemCode")
    public static let signIn = StoreButtonKind(name: "signIn")
    public static let policies = StoreButtonKind(name: "policies")
}

/// What the subscribe button of a subscription store shows.
public struct SubscriptionStoreButtonLabel: Hashable, Sendable {
    package let name: String
    public static let automatic = SubscriptionStoreButtonLabel(name: "automatic")
    public static let multiline = SubscriptionStoreButtonLabel(name: "multiline")
    public static let singleLine = SubscriptionStoreButtonLabel(name: "singleLine")
    public static let action = SubscriptionStoreButtonLabel(name: "action")
    public static let displayName = SubscriptionStoreButtonLabel(name: "displayName")
    public static let price = SubscriptionStoreButtonLabel(name: "price")
}

// MARK: - Modifiers

/// Closes a store sheet as soon as it opens: the App Store's sheets have nothing to show on the
/// web.
struct _UnavailableStoreSheet {
    let isPresented: Binding<Bool>
    let closed: () -> Void
}

// The conformance is in an extension so the modifier's initializer stays nonisolated (the
// View modifiers that make it are).
extension _UnavailableStoreSheet: ViewModifier {
    func body(content: Content) -> some View {
        content.onChange(of: isPresented.wrappedValue, initial: true) { _, presented in
            guard presented else { return }
            isPresented.wrappedValue = false
            closed()
        }
    }
}

extension View {
    /// Shows or hides a kind of button in the store views inside this view.
    nonisolated public func storeButton(_ visibility: Visibility, for buttonKinds: StoreButtonKind...) -> some View { self }

    /// Sets the icon of each plan in a subscription store.
    nonisolated public func subscriptionStoreControlIcon<V: View>(@ViewBuilder icon: @escaping (Product, Product.SubscriptionInfo) -> V) -> some View { self }

    /// Sets what a subscription store's subscribe button shows.
    nonisolated public func subscriptionStoreButtonLabel(_ label: SubscriptionStoreButtonLabel) -> some View { self }

    /// Sets the background of the plans in a subscription store's picker.
    nonisolated public func subscriptionStorePickerItemBackground<S: ShapeStyle>(_ style: S) -> some View { self }

    /// Sets the background of the plans in a subscription store's picker, in a shape.
    nonisolated public func subscriptionStorePickerItemBackground<S: ShapeStyle, T: Shape>(_ style: S, in shape: T) -> some View { self }

    /// Sets the destination of a subscription store's terms or privacy policy button.
    nonisolated public func subscriptionStorePolicyDestination(url: URL, for policy: SubscriptionStorePolicyKind) -> some View { self }

    /// Runs an action when a purchase starts in a store view inside this view. No purchase starts
    /// on the web.
    nonisolated public func onInAppPurchaseStart(perform action: (@MainActor (Product) async -> Void)?) -> some View { self }

    /// Runs an action when a purchase ends in a store view inside this view. No purchase starts
    /// on the web.
    nonisolated public func onInAppPurchaseCompletion(
        perform action: (@MainActor (Product, Result<Product.PurchaseResult, any Error>) async -> Void)?
    ) -> some View { self }

    /// Loads the statuses of a subscription group when the view appears. On the web there are
    /// none: the action gets `.success([])`.
    nonisolated public func subscriptionStatusTask(
        for groupID: String, priority: TaskPriority = .medium,
        action: @escaping @MainActor @Sendable (EntitlementTaskState<[Product.SubscriptionInfo.Status]>) async -> Void
    ) -> some View {
        task(priority: priority) { await action(.success([])) }
    }

    /// Loads the customer's entitlement to a product when the view appears. On the web there is
    /// none: the action gets `.success(nil)`.
    nonisolated public func currentEntitlementTask(
        for productID: String, priority: TaskPriority = .medium,
        action: @escaping @MainActor @Sendable (EntitlementTaskState<VerificationResult<Transaction>?>) async -> Void
    ) -> some View {
        task(priority: priority) { await action(.success(nil)) }
    }

    /// Shows the App Store's subscription management. There is none on the web, so the sheet
    /// closes as soon as it opens.
    nonisolated public func manageSubscriptionsSheet(isPresented: Binding<Bool>) -> some View {
        modifier(_UnavailableStoreSheet(isPresented: isPresented, closed: {}))
    }

    nonisolated public func manageSubscriptionsSheet(isPresented: Binding<Bool>, subscriptionGroupID: String) -> some View {
        modifier(_UnavailableStoreSheet(isPresented: isPresented, closed: {}))
    }

    /// Shows the App Store's offer code redemption. There is none on the web: the sheet closes
    /// as soon as it opens and the completion gets `StoreKitError.unsupported`.
    nonisolated public func offerCodeRedemption(isPresented: Binding<Bool>,
                                                onCompletion: @escaping (Result<Void, any Error>) -> Void = { _ in }) -> some View {
        modifier(_UnavailableStoreSheet(isPresented: isPresented, closed: { onCompletion(.failure(StoreKitError.unsupported)) }))
    }

    /// Shows the App Store's refund request for a transaction. There is none on the web: the
    /// sheet closes as soon as it opens and `onDismiss` gets `.failed`.
    nonisolated public func refundRequestSheet(
        for transactionID: Transaction.ID, isPresented: Binding<Bool>,
        onDismiss: ((Result<Transaction.RefundRequestStatus, Transaction.RefundRequestError>) -> Void)? = nil
    ) -> some View {
        modifier(_UnavailableStoreSheet(isPresented: isPresented, closed: { onDismiss?(.failure(.failed)) }))
    }
}

/// A policy a subscription store links to.
public struct SubscriptionStorePolicyKind: Hashable, Sendable {
    package let name: String
    public static let termsOfService = SubscriptionStorePolicyKind(name: "termsOfService")
    public static let privacyPolicy = SubscriptionStorePolicyKind(name: "privacyPolicy")
}
