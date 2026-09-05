// `AsyncImage`: a golden can only hold the empty phase deterministically (a URL on a non-routable
// address never resolves, and a nil URL stays empty); loaded and failed images are checked in the
// browser by Playwright/asyncimage-probe.mjs against the gallery's server.
import SwiftUI
import FixtureKit

public enum AsyncImageFixtures {
    static let missing = URL(string: "http://10.255.255.1/swiftuiweb/never.png")!

    public static let phases = Fixture("asyncimage/phases", size: CGSize(width: 360, height: 220), content: {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: missing) { image in
                    image.resizable().frame(width: 60, height: 40)
                } placeholder: {
                    Color.orange.frame(width: 60, height: 40).probe("placeholder")
                }
                .probe("withPlaceholder")
                AsyncImage(url: missing) { phase in
                    switch phase {
                    case .success(let image): image
                    case .failure: Text("Failed").probe("failed")
                    case .empty: Text("Loading").probe("loading")
                    @unknown default: Text("Unknown")
                    }
                }
                .probe("phases")
                AsyncImage(url: nil) { phase in
                    if phase.error != nil { Color.red.frame(width: 40, height: 40).probe("nilURL") } else { Color.green.frame(width: 40, height: 40) }
                }
                .probe("nilPhase")
            }
            .probe("row")
            Text("Below").probe("below")
        }
        .probe("stack")
    })

    /// Browser-only (the `probe/` prefix has no goldens and no tier enables it): the gallery's own
    /// served asset as a real URL, a missing file, and no URL; Playwright/asyncimage-probe.mjs on 8767.
    static let served = "http://127.0.0.1:8767/.build/wasm/plugins/PackageToJS/outputs/Package/assets/Assets.xcassets/badge.imageset/badge@2x.png"

    public static let live = Fixture("probe/asyncimage", size: CGSize(width: 360, height: 200), content: {
        HStack(spacing: 20) {
            AsyncImage(url: URL(string: served), scale: 2) { image in image.probe("loaded") } placeholder: { Text("Loading").probe("loadingLive") }
            AsyncImage(url: URL(string: "http://127.0.0.1:8767/missing.png")) { phase in
                if phase.error != nil { Text("Failed") } else { Text("Waiting") }
            }
            AsyncImage(url: nil) { phase in Text(phase.image == nil ? "No URL" : "Image") }
        }
    })

    public static let all: [Fixture] = [phases, live]
}
