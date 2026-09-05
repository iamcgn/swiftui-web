// SF Symbols and labels in the iOS profile: symbol sizes at the iOS text styles and the
// icon/title layout of a `Label`, alone and as list rows.
import SwiftUI
import FixtureKit

public enum IOSSymbolFixtures {
    public static let symbols = Fixture("ios/symbol/basic", size: CGSize(width: 320, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "star").probe("star")
                Image(systemName: "gear").probe("gear")
                Image(systemName: "wifi").probe("wifi")
                Image(systemName: "chevron.right").probe("chevron")
                Text("Hello").probe("text")
            }
            .probe("row")
            HStack(spacing: 12) {
                Image(systemName: "star").font(.title).probe("starTitle")
                Image(systemName: "star").font(.largeTitle).probe("starLarge")
                Image(systemName: "star").font(.footnote).probe("starFootnote")
                Image(systemName: "star").imageScale(.large).probe("starLargeScale")
                Image(systemName: "star").font(.body.weight(.bold)).probe("starBold")
            }
            .probe("sizes")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "star").probe("baselineStar")
                Text("Hello").probe("baselineText")
            }
            .probe("baseline")
        }
        .probe("stack")
    }.platform(.iOS)

    public static let labels = Fixture("ios/label/basic", size: CGSize(width: 320, height: 300)) {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text("Wi-Fi").probe("title") } icon: { Image(systemName: "wifi").probe("icon") }.probe("label")
            Label { Text("Bluetooth").probe("titleT") } icon: { Image(systemName: "gear").probe("iconT") }.font(.title).probe("labelTitle")
            Label("Wi-Fi", systemImage: "wifi").labelStyle(.iconOnly).probe("iconOnly")
            Label("Wi-Fi", systemImage: "wifi").labelStyle(.titleOnly).probe("titleOnly")
        }
        .probe("stack")
    }.platform(.iOS)

    public static let labelRows = Fixture("ios/label/list", size: CGSize(width: 320, height: 300)) {
        List {
            Label { Text("Wi-Fi").probe("title1") } icon: { Image(systemName: "wifi").probe("icon1") }.probe("row1")
            Label { Text("Bluetooth").probe("title2") } icon: { Image(systemName: "gear").probe("icon2") }.probe("row2")
            NavigationLink(destination: Text("Pushed")) {
                Label { Text("Settings").probe("title3") } icon: { Image(systemName: "star").probe("icon3") }
            }
            .probe("row3")
        }
        .probe("list")
    }.platform(.iOS)

    public static let all: [Fixture] = [symbols, labels, labelRows]
}
