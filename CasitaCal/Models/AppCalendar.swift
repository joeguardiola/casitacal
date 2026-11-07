import Foundation

extension Calendar {
    static let weekStartsOnMondayKey = "calendar.weekStartsOnMonday"

    /// The user's calendar with CasitaCal's week start (Monday by default).
    static var app: Calendar {
        var c = Calendar.current
        let monday = UserDefaults.standard.object(forKey: weekStartsOnMondayKey) as? Bool ?? true
        c.firstWeekday = monday ? 2 : 1
        return c
    }
}
