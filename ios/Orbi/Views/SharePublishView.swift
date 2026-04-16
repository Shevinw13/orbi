import SwiftUI
import PhotosUI

// MARK: - Share Publish ViewModel

@MainActor
final class SharePublishViewModel: ObservableObject {

    @Published var coverPhotoURL: String = ""
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var destination: String = ""
    @Published var budgetLevel: Int = 3
    @Published var selectedTags: Set<String> = []
    @Published var isPublishing: Bool = false
    @Published var publishError: String?
    @Published var didPublish: Bool = false
    @Published var username: String = ""
    @Published var needsUsername: Bool = false
    @Published var isSettingUsername: Bool = false

    let availableTags = ["food", "nightlife", "outdoors", "family"]

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        title.count <= 100 &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty &&
        description.count <= 500 &&
        !destination.trimmingCharacters(in: .whitespaces).isEmpty &&
        budgetLevel >= 1 && budgetLevel <= 5
    }

    func publish(tripId: String) async {
        isPublishing = true
        publishError = nil
        do {
            let request = SharedItineraryPublishRequest(
                sourceTripId: tripId,
                coverPhotoUrl: coverPhotoURL.trimmingCharacters(in: .whitespaces),
                title: title.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespaces),
                destination: destination.trimmingCharacters(in: .whitespaces),
                budgetLevel: budgetLevel,
                tags: selectedTags.isEmpty ? [] : Array(selectedTags)
            )
            // Use a task with timeout to prevent infinite hanging
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await APIClient.shared.requestVoid(
                        .post, path: "/shared-itineraries", body: request
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30s timeout
                    throw APIError.unknown(NSError(domain: "Timeout", code: -1))
                }
                // Wait for first to complete (either success or timeout)
                try await group.next()
                group.cancelAll()
            }
            didPublish = true
        } catch let error as APIError {
            if case .unauthorized = error {
                publishError = "Session expired. Please sign out and sign back in."
            } else {
                publishError = error.errorDescription
            }
        } catch {
            publishError = "Publishing timed out. The server may be waking up — try again."
        }
        isPublishing = false
    }

    func setUsername() async {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSettingUsername = true
        // Username is set via a simple PATCH to a profile endpoint or similar
        // For now we'll just dismiss the prompt
        isSettingUsername = false
        needsUsername = false
    }
}

// MARK: - Share Publish View

struct SharePublishView: View {

    let tripId: String
    let tripDestination: String
    @StateObject private var viewModel = SharePublishViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var coverImageData: Data?

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundPrimary.ignoresSafeArea()

                if viewModel.didPublish {
                    publishedConfirmation
                } else {
                    publishForm
                }
            }
            .navigationTitle("Share to Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DesignTokens.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(DesignTokens.textPrimary)
                }
            }
            .onAppear {
                viewModel.destination = tripDestination
            }
        }
    }

    private var publishForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.spacingMD) {
                // Cover Photo (optional)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cover Photo (optional)").font(.subheadline.weight(.medium)).foregroundStyle(DesignTokens.textSecondary)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        if let data = coverImageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                Text("Select a photo")
                            }
                            .foregroundStyle(DesignTokens.accentCyan)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                coverImageData = data
                            }
                        }
                    }

                    TextField("Or paste a URL (optional)", text: $viewModel.coverPhotoURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.caption)
                }

                // Title
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Title").font(.subheadline.weight(.medium)).foregroundStyle(DesignTokens.textSecondary)
                        Spacer()
                        Text("\(viewModel.title.count)/100").font(.caption2).foregroundStyle(viewModel.title.count > 100 ? .red : DesignTokens.textTertiary)
                    }
                    TextField("My Amazing Trip", text: $viewModel.title)
                        .textFieldStyle(.roundedBorder)
                }

                // Description
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Description").font(.subheadline.weight(.medium)).foregroundStyle(DesignTokens.textSecondary)
                        Spacer()
                        Text("\(viewModel.description.count)/500").font(.caption2).foregroundStyle(viewModel.description.count > 500 ? .red : DesignTokens.textTertiary)
                    }
                    TextEditor(text: $viewModel.description)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(DesignTokens.textPrimary)
                }

                // Destination (pre-filled)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Destination").font(.subheadline.weight(.medium)).foregroundStyle(DesignTokens.textSecondary)
                    TextField("City", text: $viewModel.destination)
                        .textFieldStyle(.roundedBorder)
                }

                // Budget Level
                VStack(alignment: .leading, spacing: 8) {
                    Text("Budget Level").font(.subheadline.weight(.medium)).foregroundStyle(DesignTokens.textSecondary)
                    HStack(spacing: DesignTokens.spacingSM) {
                        ForEach(1...5, id: \.self) { level in
                            let isSelected = viewModel.budgetLevel == level
                            Text(String(repeating: "$", count: level))
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
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
                                .onTapGesture { viewModel.budgetLevel = level }
                        }
                    }
                }

                // Tags
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags (optional)").font(.subheadline.weight(.medium)).foregroundStyle(DesignTokens.textSecondary)
                    HStack(spacing: 6) {
                        ForEach(viewModel.availableTags, id: \.self) { tag in
                            let isSelected = viewModel.selectedTags.contains(tag)
                            Text(tag.capitalized)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
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
                                .onTapGesture {
                                    if isSelected { viewModel.selectedTags.remove(tag) }
                                    else { viewModel.selectedTags.insert(tag) }
                                }
                        }
                    }
                }

                // Error
                if let error = viewModel.publishError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                }

                // Publish button
                Button {
                    Task { await viewModel.publish(tripId: tripId) }
                } label: {
                    HStack(spacing: DesignTokens.spacingSM) {
                        if viewModel.isPublishing {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("Publish to Explore").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(viewModel.canSubmit ? DesignTokens.accentGradient : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
                }
                .disabled(!viewModel.canSubmit || viewModel.isPublishing)
            }
            .padding(DesignTokens.spacingMD)
        }
    }

    private var publishedConfirmation: some View {
        VStack(spacing: DesignTokens.spacingLG) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Published!")
                .font(.title.weight(.bold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Your itinerary is now live in the Explore library.")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(DesignTokens.accentGradient)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(DesignTokens.spacingMD)
    }
}
