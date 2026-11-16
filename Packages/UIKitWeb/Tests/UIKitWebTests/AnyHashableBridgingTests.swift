// A hashable key out to an object and back, as RevenueCat's `[AnyHashable: Any]` attribution
// data crosses an `@objc` member: strings, numbers and booleans come back equal to the keys they
// were, so a lookup by the original key finds its entry (issue 180).
import Testing
import UIKit

#if canImport(ObjectiveC)
@Suite struct AnyHashableBridgingTests {
    @Test func keysComeBackEqualToWhatTheyWere() {
        let keys: [AnyHashable] = ["campaign", 42, true, 2.5]
        for key in keys {
            let object = key._bridgeToObjectiveC()
            let back = AnyHashable._unconditionallyBridgeFromObjectiveC(object)
            #expect(back == key)
            #expect(back.hashValue == key.hashValue)
        }
        let table: [AnyHashable: String] = ["campaign": "spring", 42: "answer", true: "yes"]
        let backKeys = keys.prefix(3).map { AnyHashable._unconditionallyBridgeFromObjectiveC($0._bridgeToObjectiveC()) }
        #expect(backKeys.map { table[$0] } == ["spring", "answer", "yes"])
    }

    @Test func aDictionaryKeyedByAnyHashableRoundTrips() {
        let data: [AnyHashable: Any] = ["campaign": "spring", 42: "answer"]
        let back = [AnyHashable: Any]._unconditionallyBridgeFromObjectiveC(data._bridgeToObjectiveC())
        #expect(back["campaign"] as? String == "spring")
        #expect(back[42] as? String == "answer")
    }
}
#endif
