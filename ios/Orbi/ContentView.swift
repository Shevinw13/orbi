import SwiftUI

// MARK: - Main Content View (Custom Floating Tab Bar)

struct ContentView: View {
    @ObservedObject var authService: AuthService
    @State private var selectedTab: AppTab = .plan

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

// MARK: - City Card (Glassmorphic Dark Theme)

struct CityCardView: View {
    let city: CityMarker
    let onPlanTrip: () -> Void
    let onDismiss: () -> Void

    @State private var imageURL: URL?

    var body: some View {
        VStack(spacing: DesignTokens.spacingMD) {
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
                            ProgressView().tint(DesignTokens.accentCyan)
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

            Text(city.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.textPrimary)

            HStack(spacing: DesignTokens.spacingSM) {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                    Text("4.8").fontWeight(.semibold).foregroundStyle(DesignTokens.textPrimary)
                }
                .font(.subheadline)
                Text("·").foregroundStyle(DesignTokens.textSecondary)
                Text(city.name).foregroundStyle(DesignTokens.textSecondary).font(.subheadline)
            }

            DestinationInsightsView(latitude: city.latitude, longitude: city.longitude)

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
        .task { await loadCityImage() }
    }

    private func loadCityImage() async {
        let searchTerms = [city.name, "\(city.name) city", "\(city.name)_(city)"]
        for term in searchTerms {
            let encoded = term.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term
            guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { continue }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let originalImage = json["originalimage"] as? [String: Any],
                   let source = originalImage["source"] as? String,
                   let imgURL = URL(string: source) {
                    imageURL = imgURL; return
                }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let thumbnail = json["thumbnail"] as? [String: Any],
                   let source = thumbnail["source"] as? String,
                   let imgURL = URL(string: source) {
                    imageURL = imgURL; return
                }
            } catch { continue }
        }
    }
}

// MARK: - Preferences Overlay

struct PreferencesOverlay: View {
    @ObservedObject var viewModel: TripPreferencesViewModel
    let onClose: () -> Void
    let onGenerate: () -> Void
    let onItineraryReady: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ScrollView {
                VStack(spacing: 18) {
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
                                .fill(LinearGradient(colors: [DesignTokens.accentCyan.opacity(0.15), DesignTokens.accentBlue.opacity(0.08)], startPoint: .top, endPoint: .bottom))
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

                    // Trip Length
                    VStack(spacing: 0) {
                        settingsRow(label: "Trip Length") {
                            HStack(spacing: 4) {
                                TextField("5", text: $viewModel.daysText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 28)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(DesignTokens.textPrimary)
                                Text("Days").foregroundStyle(DesignTokens.textSecondary)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(DesignTokens.textTertiary)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusSM))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.radiusSM).stroke(DesignTokens.surfaceGlassBorder, lineWidth: 0.5))

                    // Budget Tier
                    budgetTierSection

                    // Vibe pills (multi-select)
                    vibeSection

                    // Family Friendly toggle
                    Toggle(isOn: $viewModel.familyFriendly) {
                        HStack(spacing: DesignTokens.spacingSM) {
                            Image(systemName: "figure.and.child.holdinghands")
                                .foregroundStyle(DesignTokens.accentCyan)
                            Text("Family Friendly")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(DesignTokens.textPrimary)
                        }
                    }
                    .tint(DesignTokens.accentCyan)
                    .padding(.horizontal, DesignTokens.spacingMD)

                    // Generate button
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
                    .disabled(!viewModel.canSubmit)
                    .opacity(viewModel.canSubmit ? 1 : 0.5)

                    HStack(spacing: DesignTokens.spacingXS) {
                        Image(systemName: "sparkles").font(.caption2)
                        Text("Our travel experts are crafting your perfect itinerary").font(.caption)
                    }
                    .foregroundStyle(DesignTokens.textSecondary)
                }
                .padding(22)
                .glassmorphic(cornerRadius: DesignTokens.radiusXL)
                .padding(.horizontal, 10)
            }
            .padding(.bottom, DesignTokens.tabBarHeight + DesignTokens.spacingSM)
        }
    }

    // MARK: - Budget Tier Section

    private var budgetTierSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Budget Tier")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.textSecondary)

            HStack(spacing: DesignTokens.spacingSM) {
                ForEach(BudgetTier.allCases) { tier in
                    let isSelected = viewModel.selectedBudgetTier == tier
                    Text(tier.apiValue)
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
                        .onTapGesture { viewModel.selectedBudgetTier = tier }
                }
            }

            Text(viewModel.selectedBudgetTier.label)
                .font(.caption)
                .foregroundStyle(DesignTokens.accentCyan)
        }
    }

    // MARK: - Vibe Section (multi-select)

    private var vibeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Vibe")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                if viewModel.selectedVibes.isEmpty {
                    Text("(select at least one)")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
            HStack(spacing: 6) {
                ForEach(TripVibe.allCases) { vibe in
                    vibePill(vibe)
                }
            }
        }
    }

    private func vibePill(_ vibe: TripVibe) -> some View {
        let isSelected = viewModel.selectedVibes.contains(vibe)
        return HStack(spacing: 4) {
            Image(systemName: vibe.icon).font(.caption2)
            Text(vibe.rawValue)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
        .shadow(color: isSelected ? DesignTokens.accentCyan.opacity(0.3) : .clear, radius: 4, y: 2)
        .onTapGesture {
            if isSelected {
                viewModel.selectedVibes.remove(vibe)
            } else {
                viewModel.selectedVibes.insert(vibe)
            }
        }
    }

    private func settingsRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(DesignTokens.textPrimary)
            Spacer()
            content().font(.subheadline)
        }
        .padding(.horizontal, DesignTokens.spacingMD)
        .padding(.vertical, 14)
    }
}

// MARK: - Generating Overlay

struct GeneratingOverlay: View {
    let cityName: String
    @State private var glowOpacity: Double = 0.3
    @State private var messageIndex: Int = 0

    private let stagedMessages = [
        "Finding top spots…",
        "Optimizing your route…",
        "Finalizing your itinerary…"
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: DesignTokens.spacingLG) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [DesignTokens.accentCyan.opacity(0.6), Color.clear], center: .center, startRadius: 10, endRadius: 80))
                        .frame(width: 160, height: 160)
                        .opacity(glowOpacity)
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(DesignTokens.accentCyan)
                }
                Text(cityName).font(.title3.weight(.bold)).foregroundStyle(DesignTokens.textPrimary).padding(.horizontal, 16)
                Text(stagedMessages[messageIndex])
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .padding(.horizontal, 16)
                    .animation(.easeInOut(duration: 0.3), value: messageIndex)
                Text("Our travel professionals are planning your perfect trip")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .padding(.horizontal, 16)
                ProgressView().tint(DesignTokens.accentCyan).scaleEffect(1.3).padding(.top, DesignTokens.spacingXS)
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { glowOpacity = 0.8 }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                messageIndex = (messageIndex + 1) % stagedMessages.count
            }
        }
    }
}

// MARK: - Tabs

struct SavedTripsTab: View {
    @State private var showTrips = false
    @Binding var selectedTab: AppTab

    var body: some View {
        ZStack { DesignTokens.backgroundPrimary.ignoresSafeArea() }
            .onAppear { showTrips = true }
            .sheet(isPresented: $showTrips) {
                SavedTripsView(onPlanTrip: { selectedTab = .plan })
            }
    }
}

struct ProfileTab: View {
    @ObservedObject var authService: AuthService
    @Binding var selectedTab: AppTab
    @State private var username: String = ""
    @State private var isEditingUsername: Bool = false
    @State private var usernameError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.circle.fill").font(.system(size: 48)).foregroundStyle(DesignTokens.accentCyan)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authService.displayName ?? "User").font(.headline).foregroundStyle(DesignTokens.textPrimary)
                            if !username.isEmpty {
                                Text("@\(username)").font(.subheadline).foregroundStyle(DesignTokens.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                Section("Username") {
                    if isEditingUsername {
                        HStack {
                            TextField("Set username (max 30)", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: username) { _, newValue in
                                    if newValue.count > 30 { username = String(newValue.prefix(30)) }
                                }
                            Button("Save") {
                                isEditingUsername = false
                            }
                            .foregroundStyle(DesignTokens.accentCyan)
                            .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } else {
                        HStack {
                            Text(username.isEmpty ? "No username set" : "@\(username)")
                                .foregroundStyle(username.isEmpty ? DesignTokens.textTertiary : DesignTokens.textPrimary)
                            Spacer()
                            Button(username.isEmpty ? "Set" : "Edit") { isEditingUsername = true }
                                .foregroundStyle(DesignTokens.accentCyan)
                        }
                    }
                    if let error = usernameError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                Section {
                    Button { selectedTab = .trips } label: { Label("My Trips", systemImage: "suitcase").foregroundStyle(DesignTokens.textPrimary) }
                }
                Section {
                    Button(role: .destructive) { authService.signOut() } label: { Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") }
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

extension AppTab: Hashable {}

#Preview { ContentView(authService: AuthService.shared) }
