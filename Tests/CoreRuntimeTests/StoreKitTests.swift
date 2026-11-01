// StoreKit (sw-frameworks): the store a web page has is empty. Products don't load, transaction
// sequences end, entitlements are absent, payments fail as not allowed, a products request lists
// its identifiers as invalid, product views show their product as unavailable (to a custom style
// too) and the App Store sheets close as soon as they open.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless
import StoreKit

#if !os(WASI)
@MainActor private final class StoreLog {
    var entries: [String] = []
    var refund = true
    var redeem = true
}

/// A custom product view style that writes down what it was given.
private struct RecordingStyle: ProductViewStyle {
    let log: StoreLog
    func makeBody(configuration: Configuration) -> some View {
        var state = "other"
        if case .unavailable = configuration.state { state = "unavailable" }
        log.entries.append("\(configuration.productID) \(state) \(configuration.product == nil) \(configuration.hasCurrentEntitlement)")
        return Text(configuration.product?.displayPrice ?? "–")
    }
}

private final class PaymentObserver: SKPaymentTransactionObserver, SKProductsRequestDelegate {
    var updated: [SKPaymentTransaction] = []
    var restored = false
    var response: SKProductsResponse?
    var finished = false

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        updated += transactions
    }
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) { restored = true }
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) { self.response = response }
    func requestDidFinish(_ request: SKRequest) { finished = true }
}

@Suite @MainActor struct StoreKitTests {
    private func texts(_ runtime: Runtime) -> [String] {
        runtime.root.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }
    }

    private func render<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = MetricsTextEngine()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 480))
        _ = runtime.render(scale: 2)
        return runtime
    }

    private let annual = Product(
        id: "pro.annual", type: .autoRenewable, displayName: "Pro", description: "Every feature",
        price: Decimal(string: "29.99")!, displayPrice: "$29.99",
        subscription: Product.SubscriptionInfo(subscriptionGroupID: "pro", subscriptionPeriod: .yearly, groupLevel: 1))

    @Test func theStoreIsEmpty() async throws {
        #expect(try await Product.products(for: ["pro.annual", "pro.monthly"]).isEmpty)
        #expect(try await Product.SubscriptionInfo.status(for: "pro").isEmpty)
        #expect(await StoreKit.Transaction.currentEntitlement(for: "pro.annual") == nil)
        #expect(await StoreKit.Transaction.latest(for: "pro.annual") == nil)
        var count = 0
        for await _ in StoreKit.Transaction.all { count += 1 }
        for await _ in StoreKit.Transaction.updates { count += 1 }
        for await _ in StoreKit.Transaction.currentEntitlements { count += 1 }
        for await _ in StoreKit.Transaction.unfinished { count += 1 }
        for await _ in Product.SubscriptionInfo.Status.updates { count += 1 }
        #expect(count == 0)
        try await AppStore.sync()
        #expect(!AppStore.canMakePayments)
        await #expect(throws: StoreKitError.self) { _ = try await AppTransaction.shared }
    }

    @Test func aProductCanNotBeBought() async throws {
        await #expect(throws: Product.PurchaseError.productUnavailable) { _ = try await annual.purchase() }
        #expect(await annual.currentEntitlement == nil)
        #expect(await annual.subscription?.isEligibleForIntroOffer == false)
        #expect(annual.subscription?.subscriptionPeriod.unit.localizedDescription == "Year")
        #expect(Product.SubscriptionPeriod.Unit.month.formatted(annual.subscriptionPeriodUnitFormatStyle) == "month")
        #expect(annual.subscriptionPeriodFormatStyle.format(.everyThreeMonths) == "3 months")
        #expect(annual.price.formatted(annual.priceFormatStyle).contains("29.99"))
        #expect(annual.type == .autoRenewable && annual.type.localizedDescription == "Auto-Renewable Subscription")
    }

    @Test func verificationResults() throws {
        let transaction = StoreKit.Transaction(id: 7, productID: "seeds", productType: .consumable, purchaseDate: Date(timeIntervalSince1970: 0))
        let verified = VerificationResult<StoreKit.Transaction>.verified(transaction)
        let unverified = VerificationResult<StoreKit.Transaction>.unverified(transaction, .invalidSignature)
        #expect(try verified.payloadValue.id == 7)
        #expect(throws: VerificationResult<StoreKit.Transaction>.VerificationError.invalidSignature) { _ = try unverified.payloadValue }
        #expect(unverified.unsafePayloadValue.productID == "seeds")
        if case .consumable = transaction.productType {} else { Issue.record("product type") }
        let purchase = Product.PurchaseResult.success(verified)
        if case .success(.verified(let t)) = purchase { #expect(t.purchasedQuantity == 1) } else { Issue.record("purchase result") }
    }

    @Test func theOriginalAPIRefusesPayments() {
        let observer = PaymentObserver()
        let queue = SKPaymentQueue.default()
        queue.add(observer)
        defer { queue.remove(observer) }
        #expect(!SKPaymentQueue.canMakePayments())

        let request = SKProductsRequest(productIdentifiers: ["unlock", "tip"])
        request.delegate = observer
        request.start()
        #expect(observer.response?.products.isEmpty == true)
        #expect(observer.response?.invalidProductIdentifiers == ["tip", "unlock"])
        #expect(observer.finished)

        let product = SKProduct(productIdentifier: "unlock", localizedTitle: "Unlock", price: NSDecimalNumber(string: "1.99"), priceLocale: Locale(identifier: "en_US"))
        queue.add(SKPayment(product: product))
        #expect(observer.updated.count == 1)
        let failed = observer.updated[0]
        #expect(failed.transactionState == .failed && failed.payment.productIdentifier == "unlock")
        #expect((failed.error as? SKError)?.code == .paymentNotAllowed)
        queue.finishTransaction(failed)
        #expect(queue.transactions.isEmpty)

        queue.restoreCompletedTransactions()
        #expect(observer.restored)

        var capabilities: SKCloudServiceCapability = [.musicCatalogPlayback]
        SKCloudServiceController().requestCapabilities { capability, _ in capabilities = capability }
        #expect(capabilities.isEmpty)
        #expect(SKCloudServiceController.authorizationStatus() == .restricted)
    }

    @Test func productViewsShowTheirProductAsUnavailable() {
        let runtime = render(VStack {
            ProductView(id: "pro.annual")
            ProductView(annual)
        })
        #expect(texts(runtime) == ["Unavailable", "Pro", "Every feature", "$29.99"])

        let log = StoreLog()
        let styled = render(ProductView(id: "tip.small") { Text("icon") }.productViewStyle(RecordingStyle(log: log)))
        #expect(log.entries.last == "tip.small unavailable true false")
        #expect(texts(styled) == ["–"])
    }

    @Test func storesShowMarketingAndAnEmptyStore() {
        let runtime = render(VStack {
            StoreView(ids: ["a", "b"]) { _ in Text("never") }
            SubscriptionStoreView(groupID: "pro", visibleRelationships: .upgrade) { Text("Go Pro") }
                .containerBackground(for: .subscriptionStoreFullHeight) { Color.blue }
                .subscriptionStoreControlIcon { _, info in Text("\(info.groupLevel)") }
                .storeButton(.visible, for: .redeemCode)
                .subscriptionStoreButtonLabel(.multiline)
                .subscriptionStorePickerItemBackground(.thinMaterial)
                .onInAppPurchaseCompletion { _, _ in }
        })
        #expect(texts(runtime) == ["Unavailable", "Unavailable", "Go Pro", "Subscriptions unavailable"])
    }

    @Test func storeSheetsCloseAndTasksDeliverNoEntitlements() async {
        let log = StoreLog()
        let runtime = render(Text("Store")
            .refundRequestSheet(for: 7, isPresented: Binding(get: { log.refund }, set: { log.refund = $0 })) { result in
                if case .failure(.failed) = result { log.entries.append("refund failed") }
            }
            .offerCodeRedemption(isPresented: Binding(get: { log.redeem }, set: { log.redeem = $0 })) { result in
                if case .failure = result { log.entries.append("redeem failed") }
            }
            .subscriptionStatusTask(for: "pro") { state in
                let count = await state.map { @Sendable in $0.count }.value
                log.entries.append("statuses \(count.map { String($0) } ?? "nil")")
            })
        for _ in 0..<400 where !log.entries.contains(where: { $0.hasPrefix("statuses") }) {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(!log.refund && !log.redeem)
        #expect(Set(log.entries) == ["refund failed", "redeem failed", "statuses 0"])
        _ = runtime
    }
}
#endif
