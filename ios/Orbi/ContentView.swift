import SwiftUI
import PhotosUI

// MARK: - Main Content View (Custom Floating Tab Bar)

struct ContentView: View {
    @ObservedObject var authService: AuthService
    @State private var selectedTab: AppTab = .plan
    @State private var showUsernamePrompt: Bool = false
    @State private var usernameInput: String = ""

    var body: some View {
        ZStack {
            switch selectedTab {
            case .plan:
                PlanTab()
            case .explore:
                ExploreFeedView()
            case .trips:
                SavedTripsTab(selectedTab: $selectedTab)
            case .profile:
                ProfileTab(authService: authService, selectedTab: $selectedTab)
            }

            VStack {
                Spacer()
                FloatingTabBar(selectedTab: $selectedTab)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if authService.isAuthenticated && authService.username == nil {
                showUsernamePrompt = true
            }
        }
        .onChange(of: authService.isAuthenticated) { _, isAuth in
            if isAuth && authService.username == nil {
                showUsernamePrompt = true
            }
        }
        .sheet(isPresented: $showUsernamePrompt) {
            UsernamePromptView(
                username: $usernameInput,
                onContinue: {
                    authService.setUsername(usernameInput)
                    showUsernamePrompt = false
                }
            )
            .interactiveDismissDisabled()
        }
    }
}

// MARK: - Username Prompt View

struct UsernamePromptView: View {
    @Binding var username: String
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundPrimary.ignoresSafeArea()
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 56))
                        .foregroundStyle(DesignTokens.accentCyan)
                    Text("Choose a username")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("This is how other travelers will find you.")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .multilineTextAlignment(.center)
                    TextField("username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 40)
                        .onChange(of: username) { _, newValue in
                            if newValue.count > 30 { username = String(newValue.prefix(30)) }
                        }
                    Button(action: onContinue) {
                        Text("Continue")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(DesignTokens.accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
                    }
                    .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(username.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    .padding(.horizontal, 40)
                    Spacer()
                    Spacer()
                }
            }
        }
    }
}

// MARK: - App Tab

enum AppTab { case plan, explore, trips, profile }

// MARK: - Floating Tab Bar

private struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab

    private let tabs: [(tab: AppTab, icon: String, label: String)] = [
        (.plan, "globe.americas.fill", "Plan"),
        (.explore, "square.grid.2x2", "Explore"),
        (.trips, "suitcase.fill", "Trips"),
        (.profile, "person.fill", "Profile"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.tab) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = item.tab
                    }
                } label: {
                    VStack(spacing: DesignTokens.spacingXS) {
                        Image(systemName: item.icon)
                            .font(.system(size: 22))
                        Text(item.label)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(selectedTab == item.tab ? DesignTokens.accentCyan : DesignTokens.textSecondary)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(item.label)
            }
        }
        .frame(height: DesignTokens.tabBarHeight)
        .glassmorphic(cornerRadius: DesignTokens.radiusXL)
        .padding(.horizontal, DesignTokens.spacingLG)
        .padding(.bottom, DesignTokens.spacingSM)
    }
}


// MARK: - Plan Tab

struct PlanTab: View {
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var locationManager = LocationManager.shared
    @State private var selectedCity: CityMarker?
    @State private var flowState: ExploreFlowState = .browsing
    @StateObject private var prefsVM = PrefsViewModelHolder()
    @FocusState private var isSearchFocused: Bool
    @State private var searchQuery: String = ""

    var body: some View {
        ZStack {
            GlobeView(selectedCity: $selectedCity, userLocation: locationManager.currentLocation)
                .ignoresSafeArea()
                .padding(.top, UIScreen.main.bounds.height * 0.12)

            VStack(spacing: 0) {
                if !networkMonitor.isConnected { OfflineBannerView() }
                if flowState == .browsing || flowState == .citySelected {
                    VStack(spacing: 6) {
                        Text("Where do you want to go?")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                            .opacity(isSearchFocused ? 0 : 1)
                            .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                        SearchBarView(selectedCity: $selectedCity)
                    }
                    .padding(.top, 8)
                }
                Spacer()

                switch flowState {
                case .browsing:
                    EmptyView()
                case .citySelected:
                    if let city = selectedCity {
                        CityCardView(city: city, onPlanTrip: {
                            prefsVM.vm = TripPreferencesViewModel(city: city)
                            withAnimation(DesignTokens.sheetSpring) {
                                flowState = .preferences
                            }
                        }, onDismiss: {
                            withAnimation(DesignTokens.sheetSpring) { flowState = .browsing }
                            selectedCity = nil
                        })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, DesignTokens.spacingMD)
                        .padding(.bottom, DesignTokens.tabBarHeight + DesignTokens.spacingMD)
                    }
                case .preferences:
                    if let vm = prefsVM.vm {
                        PreferencesOverlay(viewModel: vm, onClose: {
                            withAnimation(DesignTokens.sheetSpring) { flowState = .citySelected }
                        }, onGenerate: {
                            withAnimation(DesignTokens.sheetSpring) {
                                flowState = .generating
                            }
                        }, onItineraryReady: {
                            withAnimation {
                                flowState = .tripResult
                            }
                        })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                case .generating:
                    GeneratingOverlay(cityName: selectedCity?.name ?? "")
                        .transition(.opacity)
                case .tripResult:
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
            .animation(DesignTokens.sheetSpring, value: flowState)
        }
        .onChange(of: selectedCity) { _, newCity in
            if newCity != nil && flowState == .browsing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(DesignTokens.sheetSpring) {
                        flowState = .citySelected
                    }
                }
            } else if newCity == nil { flowState = .browsing }
        }
        .onAppear {
            locationManager.requestLocation()
        }
        .fullScreenCover(isPresented: Binding(
            get: { flowState == .tripResult },
            set: { if !$0 { flowState = .browsing; selectedCity = nil } }
        )) {
            if let vm = prefsVM.vm, let itinerary = vm.generatedItinerary, let city = selectedCity {
                TripResultView(
                    itinerary: itinerary,
                    city: city,
                    vibes: vm.selectedVibes.map(\.rawValue),
                    budgetTier: vm.selectedBudgetTier.apiValue
                )
            }
        }
    }
}

enum ExploreFlowState: Equatable {
    case browsing, citySelected, preferences, generating, tripResult
}

@MainActor
class PrefsViewModelHolder: ObservableObject {
    var vm: TripPreferencesViewModel?
}

// MARK: - Saved Trips Tab

struct SavedTripsTab: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        SavedTripsView(onPlanTrip: {
            selectedTab = .plan
        })
    }
}

// MARK: - Profile Tab (FIX 1 & 3)

struct ProfileTab: View {
    @ObservedObject var authService: AuthService
    @Binding var selectedTab: AppTab

    @State private var isEditingUsername: Bool = false
    @State private var editedUsername: String = ""

    // Profile photo state (FIX 3)
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImageData: Data?

    private let profileImageKey = "orbi_profile_image_data"

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DesignTokens.spacingLG) {
                        Spacer().frame(height: 20)

                        // Profile photo (FIX 3)
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            if let data = profileImageData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(DesignTokens.accentCyan, lineWidth: 2))
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 72))
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                        }
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                    profileImageData = data
                                    UserDefaults.standard.set(data, forKey: profileImageKey)
                                }
                            }
                        }
                        .accessibilityLabel("Change profile photo")

                        // Username display (FIX 1: no user ID shown)
                        VStack(spacing: 6) {
                            if isEditingUsername {
                                HStack {
                                    TextField("Username", text: $editedUsername)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .frame(maxWidth: 200)
                                        .onChange(of: editedUsername) { _, newValue in
                                            if newValue.count > 30 { editedUsername = String(newValue.prefix(30)) }
                                        }
                                    Button("Save") {
                                        authService.setUsername(editedUsername)
                                        isEditingUsername = false
                                    }
                                    .foregroundStyle(DesignTokens.accentCyan)
                                    .disabled(editedUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            } else {
                                Text(authService.username ?? authService.displayName ?? "Traveler")
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(DesignTokens.textPrimary)
                                Button("Edit username") {
                                    editedUsername = authService.username ?? ""
                                    isEditingUsername = true
                                }
                                .font(.caption)
                                .foregroundStyle(DesignTokens.accentCyan)
                            }
                        }

                        // My Trips button (FIX 1: only one trips link)
                        Button {
                            selectedTab = .trips
                        } label: {
                            HStack {
                                Image(systemName: "suitcase.fill")
                                Text("My Trips")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.body.weight(.medium))
                            .foregroundStyle(DesignTokens.textPrimary)
                            .padding(DesignTokens.spacingMD)
                            .glassmorphic(cornerRadius: DesignTokens.radiusMD)
                        }
                        .padding(.horizontal, DesignTokens.spacingMD)

                        // Sign Out
                        Button {
                            authService.signOut()
                        } label: {
                            Text("Sign Out")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
                        }
                        .padding(.horizontal, DesignTokens.spacingMD)

                        Spacer()
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                profileImageData = UserDefaults.standard.data(forKey: profileImageKey)
            }
        }
    }
}

// MARK: - Missing Stub Views

struct CityCardView: View {
    let city: CityMarker
    let onPlanTrip: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.spacingSM) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(city.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("Tap to plan your trip")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            Button(action: onPlanTrip) {
                Text("Plan Trip")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DesignTokens.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusSM))
            }
        }
        .padding(DesignTokens.spacingMD)
        .glassmorphic(cornerRadius: DesignTokens.radiusMD)
    }
}

struct GeneratingOverlay: View {
    let cityName: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .tint(DesignTokens.accentCyan)
                .scaleEffect(1.5)
            Text("Generating itinerary for \(cityName)…")
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
        }
    }
}

struct OfflineBannerView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("You're offline")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.8))
    }
}
