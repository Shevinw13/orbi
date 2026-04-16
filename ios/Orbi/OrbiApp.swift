import SwiftUI
import SceneKit
import MapKit

@main
struct OrbiApp: App {

    @StateObject private var authService = AuthService.shared
    @State private var sharedTripId: ShareId?

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    ContentView(authService: authService)
                } else {
                    LoginView(authService: authService)
                }
            }
            .onAppear {
                authService.restoreSession()
            }
            .onOpenURL { url in
                // Handle deep links: orbi://share/{share_id} or https://api.orbi.app/share/{share_id}
                handleDeepLink(url)
            }
            .sheet(item: $sharedTripId) { shareId in
                SharedTripView(shareId: shareId.value)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        let pathComponents = url.pathComponents
        if let shareIndex = pathComponents.firstIndex(of: "share"),
           shareIndex + 1 < pathComponents.count {
            sharedTripId = ShareId(value: pathComponents[shareIndex + 1])
        }
    }
}

// Wrapper to avoid retroactive Identifiable on String
struct ShareId: Identifiable {
    let value: String
    var id: String { value }
}
