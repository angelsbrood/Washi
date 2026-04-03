import SwiftUI

@main
struct WashiCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureView()
                .frame(width: 1920, height: 1080)
                .preferredColorScheme(.light)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultSize(width: 1920, height: 1080)
    }
}
