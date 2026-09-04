// Lazy stacks and grids: LazyVStack/LazyHStack with alignment and spacing and section headers,
// LazyVGrid with fixed, flexible and adaptive columns, LazyHGrid rows. Everything is laid out
// eagerly here; the fixtures measure the layouts.
import SwiftUI
import FixtureKit

public enum LazyFixtures {
    public static let stacks = Fixture("lazy/stacks", size: CGSize(width: 320, height: 240)) {
        HStack(alignment: .top, spacing: 20) {
            LazyVStack(alignment: .leading, spacing: 6) {
                Text("Alpha").probe("alpha")
                Color.red.frame(width: 60, height: 20).probe("red")
                Text("Beta").probe("beta")
            }
            .probe("vstack")
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    Color.green.frame(width: 50, height: 20).probe("green")
                    Color.blue.frame(width: 50, height: 20)
                } header: {
                    Text("Header").probe("header")
                }
            }
            .probe("sections")
            LazyHStack(alignment: .bottom, spacing: 4) {
                Color.orange.frame(width: 20, height: 30).probe("orange")
                Text("Hi").probe("hi")
            }
            .probe("hstack")
        }
        .probe("row")
    }

    public static let grids = Fixture("lazy/grids", size: CGSize(width: 320, height: 300)) {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.fixed(60)), GridItem(.flexible()), GridItem(.flexible(minimum: 20, maximum: 80))], spacing: 4) {
                ForEach(0..<6, id: \.self) { index in
                    Color.red.frame(height: 20).probe("cell\(index)")
                }
            }
            .frame(width: 280)
            .probe("columns")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50), spacing: 10)], alignment: .leading, spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    Color.blue.frame(height: 24).probe("adaptive\(index)")
                }
            }
            .frame(width: 240)
            .probe("adaptive")
            LazyHGrid(rows: [GridItem(.fixed(30)), GridItem(.fixed(30))], spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Color.green.frame(width: 40).probe("hcell\(index)")
                }
            }
            .frame(height: 70)
            .probe("rows")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [stacks, grids]
}
