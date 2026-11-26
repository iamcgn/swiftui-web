// Camera-SwiftUI's photo processor imports Photos, UIKit and Core Image but not AVFoundation,
// and names the capture settings and CMTime: Apple's Photos makes AVFoundation visible. This
// file imports Photos alone for that reason.
import Testing
import Photos
#if !os(WASI)
import Foundation
#endif

@Suite struct PhotosBringsAVFoundationTests {
    @Test func photosImportersSeeTheCaptureTypes() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        #expect(settings.flashMode == .auto)
        let processingTime: CMTime? = CMTime(seconds: 2, preferredTimescale: 1)
        #expect(processingTime?.seconds == 2)
    }
}
