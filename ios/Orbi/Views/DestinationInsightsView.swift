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

        // Call Open-Meteo directly from the client — bypasses backend cold start
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&daily=temperature_2m_max,temperature_2m_min,weather_code&temperature_unit=fahrenheit&timezone=auto&forecast_days=1"

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid coordinates"
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let daily = json?["daily"] as? [String: Any]
            let highs = daily?["temperature_2m_max"] as? [Double]
            let lows = daily?["temperature_2m_min"] as? [Double]
            let codes = daily?["weather_code"] as? [Int]

            let tempHigh = highs?.first ?? 0
            let tempLow = lows?.first ?? 0
            let code = codes?.first ?? 0
            let condition = weatherCondition(from: code)
            let bestTime = bestTimeToVisit(latitude: latitude)

            weather = DestinationWeather(
                tempHigh: tempHigh,
                tempLow: tempLow,
                condition: condition,
                bestTimeToVisit: bestTime
            )
        } catch {
            errorMessage = "Weather unavailable"
        }
        isLoading = false
    }

    private func weatherCondition(from code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 61, 63, 65: return "Rain"
        case 71, 73, 75: return "Snow"
        case 80, 81, 82: return "Rain showers"
        case 95: return "Thunderstorm"
        default: return "Partly cloudy"
        }
    }

    private func bestTimeToVisit(latitude: Double) -> String {
        let absLat = abs(latitude)
        if absLat < 15 { return "November – March (dry season)" }
        if absLat < 30 { return "October – April (mild weather)" }
        if absLat < 50 { return "May – September (summer)" }
        return "June – August (warmest months)"
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
