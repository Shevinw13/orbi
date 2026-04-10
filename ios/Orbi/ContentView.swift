import SwiftUI

/// Root view that hosts the 3D globe as the main authenticated screen.
struct ContentView: View {

    @ObservedObject var authService: AuthService
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var selectedCity: CityMarker?
    @State private var showDestinationFlow: Bool = false
    @State private var showSavedTrips: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Full-screen 3D globe
                GlobeView(selectedCity: $selectedCity)
                    .ignoresSafeArea()
                    .accessibilityLabel("Interactive 3D globe")

                // Overlay controls
                VStack {
                    // Offline indicator (Requirement 14.3)
                    if !networkMonitor.isConnected {
                        OfflineBannerView()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Search bar floating at the top (Requirement 2.1)
                    SearchBarView(selectedCity: $selectedCity)
                        .padding(.top, 8)

                    Spacer()

                    HStack(spacing: 16) {
                        // My Trips button (Requirement 9.2)
                        Button {
                            showSavedTrips = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "suitcase.fill")
                                Text("My Trips")
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        }
                        .accessibilityLabel("My Trips")

                        Spacer()

                        Button {
                            authService.signOut()
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.subheadline)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .tint(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
            }
            .onChange(of: selectedCity) { _, newCity in
                // Requirement 2.3: On selection, open destination flow after globe animation.
                if newCity != nil {
                    // Brief delay to let the globe zoom animation start before presenting the sheet.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        showDestinationFlow = true
                    }
                }
            }
            .sheet(isPresented: $showDestinationFlow, onDismiss: {
                selectedCity = nil
            }) {
                if let city = selectedCity {
                    DestinationFlowView(city: city)
                }
            }
            .sheet(isPresented: $showSavedTrips) {
                SavedTripsView()
            }
        }
    }
}

// MARK: - Offline Banner

/// Displays a compact banner indicating the device is offline.
/// Requirement: 14.3
private struct OfflineBannerView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.subheadline)
            Text("You're offline. Requests will retry when connected.")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.9))
        .background(Color.red.opacity(0.75))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No internet connection. Requests will retry automatically when connected.")
    }
}

#Preview {
    ContentView(authService: AuthService.shared)
}
