import Foundation

/// One row of `feasts.json`. Moveable days have no `on` date; their dates are worked out below.
struct FeastEntry: Codable, Hashable, Sendable, Identifiable {
    enum Rank: String, Codable, Sendable {
        case principal, solemnity, lord, feast, memorial, optional, tradition

        var weight: Int {
            switch self {
            case .principal: 6
            case .solemnity: 5
            case .lord: 4
            case .feast: 3
            case .memorial: 2
            case .optional, .tradition: 1
            }
        }
    }

    var id: String
    /// "MM-dd"; nil for moveable days.
    var on: String?
    var name: String
    var rank: Rank
    var blurb: String
    var story: String?
    var food: [String]?
    var activities: [String]?
    /// Scripture references, such as "Luke 2:1–20".
    var readings: [String]?
    var prayers: [String]?
    var indulgence: String?

    enum CodingKeys: String, CodingKey {
        case id, on, name, rank, blurb, story, food, readings, prayers, indulgence
        case activities = "do"
    }
}

/// A feast as it falls in one particular year.
struct Celebration: Identifiable, Hashable, Sendable {
    var entry: FeastEntry
    /// "yyyy-MM-dd", matching `DayKey`.
    var dayKey: String
    var isObligation = false
    var isFastDay = false
    /// A Sunday or a higher-ranking day takes its place at Mass this year. Families often keep it anyway.
    var isOutranked = false
    var note: String?

    var id: String { "\(entry.id)-\(dayKey)" }

    var isHolyDay: Bool {
        isObligation || entry.rank == .principal || entry.rank == .solemnity
    }
}

/// The Roman calendar as kept in the dioceses of the United States, computed on the device.
struct LiturgicalCalendar: Sendable {
    let year: Int
    private let days: [String: [Celebration]]

    func celebrations(on dayKey: String) -> [Celebration] { days[dayKey] ?? [] }

    /// Western Easter (Anonymous Gregorian algorithm).
    static func easter(year y: Int) -> (month: Int, day: Int) {
        let a = y % 19, b = y / 100, c = y % 100
        let d = b / 4, e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let n = h + l - 7 * m + 114
        return (n / 31, n % 31 + 1)
    }

    /// - Parameter ascensionOnSunday: most U.S. provinces keep Ascension on the following Sunday.
    ///   Boston, Hartford, New York, Omaha and Philadelphia keep Thursday, as a holy day of obligation.
    init(year: Int, entries: [FeastEntry], ascensionOnSunday: Bool = true) {
        self.year = year
        let t = YearDates(year: year)
        let easter = t.date(Self.easter(year: year))
        let ash = t.add(easter, -46), palm = t.add(easter, -7), holySaturday = t.add(easter, -1)
        let divineMercy = t.add(easter, 7), pentecost = t.add(easter, 49)
        let corpus = t.add(easter, 63), sacredHeart = t.add(easter, 68)

        let dec3 = t.date((12, 3))
        let advent1 = t.add(dec3, -(t.weekday(dec3) - 1))
        let christmas = t.date((12, 25))
        let holyFamily = t.weekday(christmas) == 1 ? t.date((12, 30)) : t.add(christmas, 8 - t.weekday(christmas))
        let jan2 = t.date((1, 2))
        let epiphany = t.add(jan2, (8 - t.weekday(jan2)) % 7)
        let baptism = t.add(epiphany, t.dayOfMonth(epiphany) >= 7 ? 1 : 7)

        let moveable: [String: Date] = [
            "shrove-tuesday": t.add(easter, -47), "ash-wednesday": ash,
            "lent-4": t.add(easter, -21), "lent-5": t.add(easter, -14), "palm-sunday": palm,
            "holy-monday": t.add(easter, -6), "holy-tuesday": t.add(easter, -5), "spy-wednesday": t.add(easter, -4),
            "holy-thursday": t.add(easter, -3), "good-friday": t.add(easter, -2), "holy-saturday": holySaturday,
            "easter": easter, "easter-monday": t.add(easter, 1), "easter-tuesday": t.add(easter, 2),
            "easter-wednesday": t.add(easter, 3), "easter-thursday": t.add(easter, 4),
            "easter-friday": t.add(easter, 5), "easter-saturday": t.add(easter, 6),
            "divine-mercy": divineMercy,
            "ascension": t.add(easter, ascensionOnSunday ? 42 : 39), "pentecost": pentecost,
            "mary-mother-church": t.add(easter, 50), "trinity": t.add(easter, 56),
            "corpus-christi": corpus, "sacred-heart": sacredHeart, "immaculate-heart": t.add(easter, 69),
            "christ-king": t.add(advent1, -7), "advent-1": advent1, "advent-3": t.add(advent1, 14),
            "holy-family": holyFamily, "epiphany": epiphany, "baptism": baptism,
        ]

        let isSunday = { (d: Date) in t.weekday(d) == 1 }
        let isSeasonSunday = { (d: Date) in
            isSunday(d) && ((d >= ash && d <= holySaturday) || (d >= advent1 && d < christmas) || (d >= easter && d <= pentecost))
        }
        let isPrivileged = { (d: Date) in d == ash || (d >= palm && d <= divineMercy) }

        struct Placed {
            var entry: FeastEntry
            var date: Date
            var isMoveable: Bool
            var movedFrom: Date?
        }

        var placed: [Placed] = []
        for entry in entries {
            if let on = entry.on {
                let parts = on.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                let original = t.date((parts[0], parts[1]))
                var date = original
                switch entry.id {
                case "joseph" where date >= palm && date <= holySaturday:
                    date = t.add(palm, -1)
                case "annunciation" where date >= palm && date <= divineMercy:
                    date = t.add(divineMercy, 1)
                case "john-baptist" where date == sacredHeart:
                    date = t.add(date, -1)
                case "unborn" where isSunday(date):
                    date = t.add(date, 1)
                default:
                    if entry.rank == .solemnity, isSeasonSunday(date) || date == sacredHeart || date == corpus {
                        date = t.add(date, 1)
                    }
                }
                placed.append(Placed(entry: entry, date: date, isMoveable: false, movedFrom: date == original ? nil : original))
            } else if let date = moveable[entry.id] {
                placed.append(Placed(entry: entry, date: date, isMoveable: true))
            }
        }

        var result: [String: [Celebration]] = [:]
        for (key, items) in Dictionary(grouping: placed, by: { t.key($0.date) }) {
            let date = items[0].date
            let weekday = t.weekday(date)
            let heaviest = items.filter { $0.entry.rank != .tradition }.map(\.entry.rank.weight).max() ?? 0

            var day: [Celebration] = []
            for item in items {
                var c = Celebration(entry: item.entry, dayKey: key)
                if let from = item.movedFrom { c.note = "Moved from \(t.monthDayText(from)) this year." }

                switch item.entry.rank {
                case .principal, .solemnity, .tradition:
                    break
                case .lord:
                    c.isOutranked = heaviest > 4
                case .feast:
                    c.isOutranked = heaviest > 3 || (!item.isMoveable && (isSunday(date) || isPrivileged(date)))
                case .memorial, .optional:
                    c.isOutranked = heaviest >= 3 || (!item.isMoveable && (isSunday(date) || isPrivileged(date)))
                }
                if c.isOutranked {
                    c.note = "A Sunday or a higher feast takes its place at Mass this year, but it's still a good day to celebrate at home."
                }

                switch item.entry.id {
                case "christmas":
                    c.isObligation = true
                case "immaculate":
                    c.isObligation = item.movedFrom == nil
                    if item.movedFrom != nil {
                        c.note = "Moved from December 8, a Sunday this year. The Mass obligation doesn't move with it."
                    }
                case "ascension":
                    c.isObligation = !ascensionOnSunday
                case "mary-mother-god", "assumption", "all-saints":
                    if weekday == 7 || weekday == 2 {
                        c.note = "A holy day, but the Mass obligation is lifted this year because it falls on a \(weekday == 7 ? "Saturday" : "Monday")."
                    } else {
                        c.isObligation = true
                    }
                case "ash-wednesday", "good-friday":
                    c.isFastDay = true
                default:
                    break
                }
                day.append(c)
            }
            result[key] = day.sorted {
                ($0.isOutranked ? 1 : 0, -$0.entry.rank.weight, $0.entry.name) < ($1.isOutranked ? 1 : 0, -$1.entry.rank.weight, $1.entry.name)
            }
        }
        days = result
    }
}

/// Date arithmetic in a fixed zone, so feasts never drift with the device's time zone.
private struct YearDates {
    let year: Int
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    func date(_ md: (month: Int, day: Int)) -> Date {
        calendar.date(from: DateComponents(year: year, month: md.month, day: md.day)) ?? .distantPast
    }

    func add(_ d: Date, _ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: d) ?? d }
    /// 1 = Sunday.
    func weekday(_ d: Date) -> Int { calendar.component(.weekday, from: d) }
    func dayOfMonth(_ d: Date) -> Int { calendar.component(.day, from: d) }

    func key(_ d: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func monthDayText(_ d: Date) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August",
                     "September", "October", "November", "December"]
        return "\(names[calendar.component(.month, from: d) - 1]) \(dayOfMonth(d))"
    }
}
