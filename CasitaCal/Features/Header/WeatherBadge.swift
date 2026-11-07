import SwiftUI
import WeatherKit

/// Compact weather in the header (tap for a 5-day forecast) or large on the slideshow.
struct WeatherBadge: View {
    enum Style { case header, large }
    var style: Style = .header

    @Environment(WeatherStore.self) private var weather
    @State private var showForecast = false

    var body: some View {
        Group {
            if let s = weather.snapshot {
                Button { showForecast = style == .header } label: {
                    HStack(spacing: 10) {
                        Image(systemName: s.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: style == .large ? 52 : 34))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Self.temp(s.temperature))
                                .font(.system(size: style == .large ? 52 : 30, weight: .semibold, design: .rounded))
                            if let hi = s.high, let lo = s.low {
                                Text("H \(Self.temp(hi))  L \(Self.temp(lo))")
                                    .font(style == .large ? .title3 : .subheadline)
                                    .opacity(0.75)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showForecast) { ForecastPopover() }
                .accessibilityLabel("\(s.condition), \(Self.temp(s.temperature))")
            } else if style == .header {
                Button { showForecast = true } label: {
                    Label("--°", systemImage: "cloud.sun")
                        .font(.title2.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.inkSecondary)
                .popover(isPresented: $showForecast) { ForecastPopover() }
            }
        }
    }

    static func temp(_ m: Measurement<UnitTemperature>) -> String {
        m.formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// 5-day forecast + Apple Weather attribution (required by WeatherKit).
struct ForecastPopover: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = weather.snapshot {
                Text(s.condition).font(.title2.weight(.bold))
                if let p = s.precipitationChance, p > 0 {
                    Label("\(Int(p * 100))% chance of rain today", systemImage: "umbrella")
                        .foregroundStyle(.secondary)
                }
                Divider()
                ForEach(s.upcoming) { day in
                    HStack {
                        Text(Calendar.app.isDateInToday(day.date) ? "Today" : day.date.formatted(.dateTime.weekday(.wide)))
                            .frame(width: 110, alignment: .leading)
                        Image(systemName: day.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 34)
                        Text(day.precipitationChance >= 0.2 ? "\(Int(day.precipitationChance * 100))%" : "")
                            .font(.caption).foregroundStyle(.blue)
                            .frame(width: 40)
                        Spacer()
                        Text(WeatherBadge.temp(day.low)).foregroundStyle(.secondary)
                        Text(WeatherBadge.temp(day.high)).fontWeight(.semibold)
                    }
                    .font(.title3)
                }
                if let a = weather.attribution {
                    Divider()
                    HStack {
                        AsyncImage(url: scheme == .dark ? a.combinedMarkDarkURL : a.combinedMarkLightURL) { img in
                            img.resizable().scaledToFit()
                        } placeholder: { Text(" Weather") }
                        .frame(height: 14)
                        Spacer()
                        Button("Data sources") { openURL(a.legalPageURL) }.font(.caption)
                    }
                }
            } else {
                Text("Weather").font(.title2.weight(.bold))
                statusMessage
            }
        }
        .padding(22)
        .frame(width: 380)
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch weather.status {
        case .needsLocationPermission:
            Text("CasitaCal needs the iPad's location to show local weather.")
            Button("Allow location") { Task { await weather.requestPermission() } }
                .buttonStyle(.borderedProminent)
        case .locationDenied:
            Text("Location is off for CasitaCal. Turn it on in Settings → Privacy & Security → Location Services → CasitaCal.")
        case let .unavailable(why):
            Text(why).foregroundStyle(.secondary)
        default:
            ProgressView()
        }
    }
}
