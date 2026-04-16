import SwiftUI

// MARK: - WeatherViewModel (Req 17.1, 17.2, 17.3, 17.5, 17.6)

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var weather: DestinationWeather?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    func loadWeather(latitude: Double, longitude: Double) async {
        isLoading = true
        errorMessage = nil
        do {
            let response: DestinationWeather = try await APIClient.shared.request(
                .get, path: "/destinations/weather",
                queryItems: [
                    URLQueryItem(name: "latitude", value: String(latitude)),
                    URLQueryItem(name: "longitude", value: String(longitude)),
                ],
                requiresAuth: false
            )
            weather = response
        } catch {
            errorMessage = "Weather data unavailable"
            weather = nil
        }
        isLoading = false
    }
}

// MARK: - DestinationInsightsView (Req 17.1, 17.2, 17.5, 17.6)

struct DestinationInsightsView: View {
    let latitude: Double
    let longitude: Double

    @StateObject private var weatherVM = WeatherViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
            Label("Destination Insights", systemImage: "cloud.sun")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(DesignTokens.textPrimary)

            if weatherVM.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(DesignTokens.accentCyan)
                    Spacer()
                }
                .padding(.vertical, DesignTokens.spacingSM)
            } else if let weather = weatherVM.weather {
                VStack(alignment: .leading, spacing: DesignTokens.spacingSM) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Weather")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textSecondary)
                        HStack(spacing: 6) {
                            Image(systemName: weatherIcon(weather.condition))
                                .foregroundStyle(DesignTokens.accentCyan)
                            Text(weather.condition)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DesignTokens.textPrimary)
                        }
                        Text("H: \(Int(weather.tempHigh))°F  L: \(Int(weather.tempLow))°F")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }

                    Divider()
                        .overlay(DesignTokens.surfaceGlassBorder)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Best Time to Visit")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.textSecondary)
                        Text(weather.bestTimeToVisit)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DesignTokens.accentCyan)
                    }
                }
                .padding(DesignTokens.spacingSM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassmorphic(cornerRadius: DesignTokens.radiusSM)
            } else if let error = weatherVM.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.textTertiary)
                    .padding(DesignTokens.spacingSM)
            }
        }
        .task {
            await weatherVM.loadWeather(latitude: latitude, longitude: longitude)
        }
    }

    private func weatherIcon(_ condition: String) -> String {
        let lower = condition.lowercased()
        if lower.contains("rain") { return "cloud.rain" }
        if lower.contains("cloud") { return "cloud" }
        if lower.contains("snow") { return "cloud.snow" }
        if lower.contains("clear") || lower.contains("sunny") { return "sun.max" }
        return "cloud.sun"
    }
}
