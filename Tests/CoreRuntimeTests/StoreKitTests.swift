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

private final class ReceiptRefresh: SKRequestDelegate {
    var failure: (any Error)?
    var finished = false
    func requestDidFinish(_ request: SKRequest) { finished = true }
    func request(_ request: SKRequest, didFailWithError error: any Error) { failure = error }
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
        #expect(transaction.storefront.countryCode == "USA")
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

        // RevenueCat's receipt refresh: there is no App Store receipt to fetch on the web.
        let refresh = ReceiptRefresh()
        let receiptRequest: SKRequest = SKReceiptRefreshRequest()
        receiptRequest.delegate = refresh
        receiptRequest.start()
        #expect((refresh.failure as? SKError)?.code == .unknown && !refresh.finished)
        #expect(SKReceiptRefreshRequest(receiptProperties: [SKReceiptPropertyIsExpired: true]).receiptProperties?.count == 1)

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
            StoreView(ids: ["c"], prefersPromotionalIcon: true)
            SubscriptionStoreView(groupID: "pro", visibleRelationships: .upgrade) { Text("Go Pro") }
                .containerBackground(for: .subscriptionStoreFullHeight) { Color.blue }
                .subscriptionStoreControlIcon { _, info in Text("\(info.groupLevel)") }
                .storeButton(.visible, for: .redeemCode)
                .subscriptionStoreButtonLabel(.multiline)
                .subscriptionStorePickerItemBackground(.thinMaterial)
                .onInAppPurchaseCompletion { _, _ in }
        })
        #expect(texts(runtime) == ["Unavailable", "Unavailable", "Unavailable", "Go Pro", "Subscriptions unavailable"])
    }

    @Test func aStoreBuiltFromStoreContentShowsTheNote() {
        let runtime = render(VStack {
            SubscriptionStoreView(productIDs: ["pro.monthly", "pro.yearly"]) {
                EmptyStoreContent()
                EmptyStoreContent()
            }
            SubscriptionStoreView(groupID: "pro")
        })
        #expect(texts(runtime) == ["Subscriptions unavailable", "Subscriptions unavailable"])
    }

    @Test func billingPlansPurchaseIntentsAndTheCustomLinkAreEmpty() async throws {
        let plan: Product.SubscriptionInfo.BillingPlanType = .monthly
        switch plan {
        case .upFront: Issue.record("monthly matched upFront")
        case .monthly: break
        default: Issue.record("monthly matched nothing")
        }
        let terms = Product.SubscriptionInfo.PricingTerms(
            billingPlanType: .monthly, billingPrice: 4.99, billingDisplayPrice: "$4.99",
            commitmentInfo: .init(period: .yearly))
        #expect(terms.commitmentInfo.period == .yearly)
        #expect(terms.subscriptionOffers.isEmpty)

        // No purchase intent arrives: the sequence waits until its task is cancelled.
        let waiting = Task { () -> Int in
            var count = 0
            for await _ in PurchaseIntent.intents { count += 1 }
            return count
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        waiting.cancel()
        #expect(await waiting.value == 0)

        #expect(await ExternalPurchaseCustomLink.isEligible == false)
        #expect(try await ExternalPurchaseCustomLink.token(for: "ACQUISITION") == nil)
        await #expect(throws: StoreKitError.self) { try await ExternalPurchaseCustomLink.showNotice(type: .browser) }
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
                let count = await state.map { @Sendable statuses in statuses.count }.value
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
@Suite struct StoreKitOfferTests {
    @Test func noStorefrontAndNoDiscounts() async {
        #expect(await Storefront.current == nil)
        var count = 0
        for await _ in Storefront.updates { count += 1 }
        #expect(count == 0)
        let queue = SKPaymentQueue.default()
        #expect(queue.storefront == nil)
        #expect(queue.delegate == nil)
        let product = SKProduct(productIdentifier: "pro", localizedTitle: "Pro", price: NSDecimalNumber(string: "4.99"), priceLocale: Locale(identifier: "en_US"))
        #expect(product.introductoryPrice == nil)
        #expect(product.discounts.isEmpty)
    }

    @Test func mutablePaymentCarriesItsDiscount() {
        let product = SKProduct(productIdentifier: "pro", localizedTitle: "Pro", price: NSDecimalNumber(string: "4.99"), priceLocale: Locale(identifier: "en_US"))
        let payment = SKMutablePayment(product: product)
        #expect(payment.paymentDiscount == nil)
        let discount = SKPaymentDiscount(identifier: "offer", keyIdentifier: "key", nonce: UUID(), signature: "sig", timestamp: 1)
        payment.paymentDiscount = discount
        payment.simulatesAskToBuyInSandbox = true
        #expect(payment.paymentDiscount?.identifier == "offer")
        #expect(payment.simulatesAskToBuyInSandbox)
    }

    @Test func errorKeepsItsUserInfo() {
        let error = SKError(.paymentNotAllowed, userInfo: [NSLocalizedDescriptionKey: "No payments"])
        #expect(error.userInfo[NSLocalizedDescriptionKey] as? String == "No payments")
        #expect(error.errorCode == 4)
        #expect(error == SKError(.paymentNotAllowed))
        #expect(SKError.errorDomain == "SKErrorDomain")
        #expect(SKError(.paymentMethodBindingConfigurationRequired).errorCode == 21)
    }

    @Test func purchaseOptionsCollectInASet() throws {
        let offer = Product.SubscriptionOffer(id: "back", type: .winBack, price: 0, displayPrice: "Free",
                                              period: .monthly, periodCount: 1, paymentMode: .freeTrial)
        var options: Set<Product.PurchaseOption> = [.winBackOffer(offer), .introductoryOfferEligibility(compactJWS: "jws")]
        options.formUnion(Product.PurchaseOption.promotionalOffer("spring", compactJWS: "signed"))
        options.insert(.promotionalOffer(offerID: "spring", keyID: "key", nonce: UUID(), signature: Data([1, 2]), timestamp: 3))
        options.insert(.billingPlanType(.monthly))
        options.insert(.billingPlanType(.monthly))
        #expect(options.count == 6)
        #expect(Product.PurchaseError.paymentMethodBindingConfigurationRequired != .productUnavailable)
    }

    @Test func productAndTransactionDescribeThemselves() throws {
        let annual = Product(id: "pro.annual", type: .autoRenewable, displayName: "Pro \"Plus\"", description: "Every\nfeature",
                             price: Decimal(string: "29.99")!, displayPrice: "$29.99", currencyCode: "EUR",
                             subscription: Product.SubscriptionInfo(subscriptionGroupID: "pro", subscriptionPeriod: .yearly))
        #expect(annual.subscription?.winBackOffers.isEmpty == true)
        let json = try #require(JSONSerialization.jsonObject(with: annual.jsonRepresentation) as? [String: Any])
        #expect(json["id"] as? String == "pro.annual")
        let attributes = try #require(json["attributes"] as? [String: Any])
        #expect(attributes["name"] as? String == "Pro \"Plus\"")
        let offers = try #require(attributes["offers"] as? [[String: Any]])
        #expect(offers.first?["currencyCode"] as? String == "EUR")
        #expect(offers.first?["price"] as? String == "29.99")
        let transaction = StoreKit.Transaction(id: 7, productID: "seeds", productType: .consumable, purchaseDate: Date(timeIntervalSince1970: 0))
        #expect(transaction.environmentStringRepresentation == "Production")
        #expect(transaction.billingPlanType == nil)
    }
}
#endif
