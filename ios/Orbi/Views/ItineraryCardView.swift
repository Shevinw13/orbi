import SwiftUI

// MARK: - Itinerary Card View (Explore Feed)

/// Visual card for the Explore feed — large destination image with overlay text.
struct ItineraryCardView: View {

    let card: SharedItineraryCard
    @State private var imageURL: URL?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background image
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        gradientPlaceholder
                    }
                }
            } else {
                gradientPlaceholder
            }
        }
        .frame(width: 260, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
        .overlay(alignment: .bottomLeading) {
            // Text overlay with gradient scrim
            VStack(alignment: .leading, spacing: 4) {
                Spacer()

                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption2)
                        Text(card.destination)
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.85))

                    HStack(spacing: 10) {
                        Label("\(card.numDays)d", systemImage: "calendar")
                        Text(budgetIndicator)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                        Spacer()
                        if let username = card.creatorUsername, !username.isEmpty {
                            Text("@\(username)")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        HStack(spacing: 2) {
                            Image(systemName: "bookmark.fill")
                            Text("\(card.saveCount)")
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, DesignTokens.spacingSM)
                .padding(.bottom, DesignTokens.spacingSM)
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusMD))
        }
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .task { await loadDestinationImage() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title), \(card.destination), \(card.numDays) days")
    }

    private var budgetIndicator: String {
        String(repeating: "$", count: max(1, min(5, card.budgetLevel)))
    }

    private var gradientPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [DesignTokens.accentCyan.opacity(0.4), DesignTokens.accentBlue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 32))
                Text(card.destination)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func loadDestinationImage() async {
        // Use cover photo if available
        if let urlStr = card.coverPhotoUrl, !urlStr.isEmpty, let url = URL(string: urlStr) {
            imageURL = url
            return
        }

        // Fall back to Wikipedia image
        let terms = [card.destination, "\(card.destination) city"]
        for term in terms {
            let encoded = term.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? term
            guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else { continue }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let img = (json["originalimage"] as? [String: Any])?["source"] as? String
                    ?? (json["thumbnail"] as? [String: Any])?["source"] as? String,
                   let imgURL = URL(string: img) {
                    imageURL = imgURL
                    return
                }
            } catch { continue }
        }
    }
}
