import SwiftUI

// MARK: - Main Content View (Custom Floating Tab Bar)

struct ContentView: View {
    @ObservedObject var authService: AuthService
    @State private var selectedTab: AppTab = .explore

    var body: some View {
        ZStack {
            // Selected tab content (fullscreen)
            switch selectedTab {
            case .explore:
                ExploreTab()
            case .trips:
                SavedTripsTab()
            case .profile:
                ProfileTab(authService: authService)
            }

            // Floating tab bar at bottom
            VStack {
                Spacer()
                FloatingTabBar(selectedTab: $selectedTab)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - App Tab

enum AppTab { case explore, trips, profile }

// MARK: - Floating Tab Bar

private struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab

    private let tabs: [(tab: AppTab, icon: String, label: String)] = [
        (.explore, "globe.americas.fill", "Explore"),
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

// MARK: - Explore Tab

struct ExploreTab: View {
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var locationManager = LocationManager.shared
    @State private var selectedCity: CityMarker?
    @State private var flowState: ExploreFlowState = .browsing
    @StateObject private var prefsVM = PrefsViewModelHolder()

    var body: some View {
        ZStack {
            GlobeView(selectedCity: $selectedCity, userLocation: locationManager.currentLocation)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if !networkMonitor.isConnected { OfflineBannerView() }
                if flowState == .browsing || flowState == .citySelected {
                    SearchBarView(selectedCity: $selectedCity)
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
                    EmptyView() // Handled by fullScreenCover below
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
                    hotelPriceRange: vm.hotelPriceRange.rawValue,
                    hotelVibe: vm.hotelVibe == .none ? nil : vm.hotelVibe.rawValue,
                    restaurantPriceRange: vm.restaurantPriceRange.rawValue,
                    cuisineType: vm.cuisineType.isEmpty ? nil : vm.cuisineType
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


// MARK: - City Card (Glassmorphic Dark Theme — ~30% sheet)

struct CityCardView: View {
    let city: CityMarker
    let onPlanTrip: () -> Void
    let onDismiss: () -> Void

    @State private var imageURL: URL?

    var body: some View {
        VStack(spacing: DesignTokens.spacingMD) {
            // Dismiss button
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            }

            // Hero image from Wikipedia
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.radiusMD)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.accentCyan.opacity(0.3),
                                DesignTokens.accentBlue.opacity(0.2),
                                DesignTokens.backgroundSecondary,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 140)

                if let url = imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
                        default:
                            ProgressView()
                                .tint(DesignTokens.accentCyan)
                        }
                    }
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(DesignTokens.accentCyan)
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))

            // City name
            Text(city.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.textPrimary)

            // Rating + country label
            HStack(spacing: DesignTokens.spacingSM) {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("4.8")
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignTokens.textPrimary)
                }
                .font(.subheadline)

                Text("·")
                    .foregroundStyle(DesignTokens.textSecondary)
                Text(city.name)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .font(.subheadline)
            }

            // Destination Insights (Req 17.5)
            DestinationInsightsView(latitude: city.latitude, longitude: city.longitude)

            // Plan Trip button with accent gradient
            Button(action: onPlanTrip) {
                Text("Plan Trip")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(DesignTokens.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
                    .shadow(color: DesignTokens.accentCyan.opacity(0.3), radius: 8, y: 4)
            }
        }
        .padding(22)
        .glassmorphic(cornerRadius: DesignTokens.radiusXL)
        .shadow(color: Color.black.opacity(0.4), radius: 20, y: 8)
        .task {
            await loadCityImage()
        }
    }

    // Fetch city image from Wikipedia REST API (free, no key needed)
    // Tries the city name directly, then with "_city" suffix for better matches
    private func loadCityImage() async {
        let searchTerms = [
            city.name,
            "\(city.name) city",
            "\(city.name)_(city)",
        ]

        for term in searchTerms {
            let encoded = term
                .replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term
            guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else { continue }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { continue }

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let originalImage = json["originalimage"] as? [String: Any],
                   let source = originalImage["source"] as? String,
                   let imgURL = URL(string: source) {
                    imageURL = imgURL
                    return
                }
                // Fallback to thumbnail if no originalimage
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let thumbnail = json["thumbnail"] as? [String: Any],
                   let source = thumbnail["source"] as? String,
                   let imgURL = URL(string: source) {
                    imageURL = imgURL
                    return
                }
            } catch {
                continue
            }
        }
    }
}


// MARK: - Preferences Overlay (Glassmorphic Dark Theme — ~80% sheet)

struct PreferencesOverlay: View {
    @ObservedObject var viewModel: TripPreferencesViewModel
    let onClose: () -> Void
    let onGenerate: () -> Void
    let onItineraryReady: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                // Back button
                HStack {
                    Button(action: onClose) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignTokens.accentCyan)
                    }
                    Spacer()
                }

                // City header
                VStack(spacing: DesignTokens.spacingSM) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DesignTokens.accentCyan.opacity(0.15), DesignTokens.accentBlue.opacity(0.08)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(width: 60, height: 60)
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(DesignTokens.accentCyan)
                    }
                    Text(viewModel.city.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("Plan a trip to \(viewModel.city.name)?")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                // Settings rows
                VStack(spacing: 0) {
                    settingsRow(label: "Trip Length") {
                        HStack(spacing: 4) {
                            TextField("5", text: $viewModel.daysText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 28)
                                .fontWeight(.semibold)
                                .foregroundStyle(DesignTokens.textPrimary)
                            Text("Days")
                                .foregroundStyle(DesignTokens.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.textTertiary)
                        }
                    }
                    Divider()
                        .overlay(DesignTokens.surfaceGlassBorder)
                        .padding(.leading, DesignTokens.spacingMD)
                    settingsRow(label: "Hotel Preferences") {
                        HStack(spacing: 4) {
                            Text(viewModel.hotelPriceRange.rawValue)
                                .fontWeight(.semibold)
                                .foregroundStyle(DesignTokens.textPrimary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.textTertiary)
                        }
                    }
                }
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusSM))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.radiusSM)
                        .stroke(DesignTokens.surfaceGlassBorder, lineWidth: 0.5)
                )

                // Hotel price pills
                HStack(spacing: DesignTokens.spacingSM) {
                    ForEach(PriceRange.allCases) { range in
                        let isSelected = viewModel.hotelPriceRange == range
                        Text(range.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Group {
                                    if isSelected {
                                        Capsule().fill(DesignTokens.accentGradient)
                                    } else {
                                        Capsule().stroke(DesignTokens.surfaceGlassBorder, lineWidth: 1)
                                    }
                                }
                            )
                            .foregroundStyle(isSelected ? .white : DesignTokens.textSecondary)
                            .clipShape(Capsule())
                            .onTapGesture { viewModel.hotelPriceRange = range }
                    }
                }

                // Vibe pills
                VStack(alignment: .leading, spacing: 10) {
                    Text("Vibe")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DesignTokens.textSecondary)
                    HStack(spacing: DesignTokens.spacingSM) {
                        ForEach(TripVibe.allCases) { vibe in
                            vibePill(vibe)
                        }
                    }
                }

                // Generate Itinerary button — full-width accent gradient
                Button {
                    Task {
                        onGenerate()
                        await viewModel.submit()
                        if viewModel.generatedItinerary != nil {
                            onItineraryReady()
                        }
                    }
                } label: {
                    HStack(spacing: DesignTokens.spacingSM) {
                        Image(systemName: "sparkles")
                        Text("Generate Itinerary").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(DesignTokens.accentGradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
                    .shadow(color: DesignTokens.accentCyan.opacity(0.3), radius: 8, y: 4)
                }

                HStack(spacing: DesignTokens.spacingXS) {
                    Image(systemName: "sparkles").font(.caption2)
                    Text("Our travel experts are crafting your perfect itinerary").font(.caption)
                }
                .foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(22)
            .glassmorphic(cornerRadius: DesignTokens.radiusXL)
            .padding(.horizontal, 10)
            .padding(.bottom, DesignTokens.tabBarHeight + DesignTokens.spacingSM)
        }
    }

    // MARK: - Settings Row

    private func settingsRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            content().font(.subheadline)
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, 14)
    }

    // MARK: - Vibe Pill

    private func vibePill(_ vibe: TripVibe) -> some View {
        let isSelected = viewModel.selectedVibe == vibe
        return Text(vibe.rawValue)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Group {
                    if isSelected {
                        Capsule().fill(DesignTokens.accentGradient)
                    } else {
                        Capsule().stroke(DesignTokens.surfaceGlassBorder, lineWidth: 1)
                    }
                }
            )
            .foregroundStyle(isSelected ? .white : DesignTokens.textSecondary)
            .clipShape(Capsule())
            .onTapGesture { viewModel.selectedVibe = vibe }
    }
}


// MARK: - Generating Overlay (Translucent dark + glow pulse)

struct GeneratingOverlay: View {
    let cityName: String
    @State private var glowOpacity: Double = 0.3

    var body: some View {
        ZStack {
            // Translucent dark background — globe remains visible
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: DesignTokens.spacingLG) {
                Spacer()

                // Pulsing glow circle
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [DesignTokens.accentCyan.opacity(0.6), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .opacity(glowOpacity)

                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(DesignTokens.accentCyan)
                }

                // City name
                Text(cityName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(DesignTokens.textPrimary)

                // Generating text
                Text("Generating your itinerary…")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.textPrimary)

                Text("Our travel professionals are planning your perfect trip")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)

                // Cyan-tinted ProgressView
                ProgressView()
                    .tint(DesignTokens.accentCyan)
                    .scaleEffect(1.3)
                    .padding(.top, DesignTokens.spacingXS)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowOpacity = 0.8
            }
        }
    }
}

// MARK: - Tabs

struct SavedTripsTab: View {
    @State private var showTrips = false

    var body: some View {
        ZStack {
            DesignTokens.backgroundPrimary.ignoresSafeArea()
        }
        .onAppear { showTrips = true }
        .sheet(isPresented: $showTrips) {
            SavedTripsView()
        }
    }
}

struct ProfileTab: View {
    @ObservedObject var authService: AuthService
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(DesignTokens.accentCyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authService.displayName ?? authService.userId ?? "Traveler")
                                .font(.headline)
                                .foregroundStyle(DesignTokens.textPrimary)
                            Text("Orbi Explorer")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section("Account") {
                    NavigationLink {
                        Text("Settings")
                            .navigationTitle("Settings")
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    NavigationLink {
                        SavedTripsView()
                    } label: {
                        Label("Saved Trips", systemImage: "suitcase")
                    }
                }
                Section("Preferences") {
                    NavigationLink {
                        Text("Preferences")
                            .navigationTitle("Preferences")
                    } label: {
                        Label("Preferences", systemImage: "slider.horizontal.3")
                    }
                    Label("Notifications", systemImage: "bell")
                    Label("Appearance", systemImage: "paintbrush")
                }
                Section {
                    Button(role: .destructive) { authService.signOut() } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .scrollContentBackground(.hidden)
            .background(DesignTokens.backgroundPrimary)
        }
    }
}

private struct OfflineBannerView: View {
    var body: some View {
        HStack(spacing: DesignTokens.spacingSM) {
            Image(systemName: "wifi.slash").font(.subheadline)
            Text("You're offline").font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, DesignTokens.spacingSM)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.8))
    }
}

// MARK: - Hashable Conformance for AppTab

extension AppTab: Hashable {}

#Preview { ContentView(authService: AuthService.shared) }
