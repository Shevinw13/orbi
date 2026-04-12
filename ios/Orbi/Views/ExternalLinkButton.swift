import SwiftUI

/// A small reusable "View" link that opens Google Maps search for a place.
/// Validates: Requirements 7.1, 7.2, 7.3, 7.4
struct ExternalLinkButton: View {
    let placeName: String
    let city: String

    private var url: URL? {
        let query = "\(placeName) \(city)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)")
    }

    var body: some View {
        if let url = url {
            Link(destination: url) {
                Text("View")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.accentCyan)
            }
            .accessibilityLabel("View \(placeName) on Google Maps")
        }
    }
}
