import CoreData

/// Feast days added to the calendar. They're stored with the household (so every device shows
/// them) and drawn at the bottom of the day. Nothing is sent to Google.
enum FeastPins {
    static func pins(day: String, feastID: String, context: NSManagedObjectContext) -> [CDFeastPin] {
        let request = NSFetchRequest<CDFeastPin>(entityName: "CDFeastPin")
        request.predicate = NSPredicate(format: "day == %@ AND feastID == %@", day, feastID)
        return (try? context.fetch(request)) ?? []
    }

    static func isPinned(_ c: Celebration, context: NSManagedObjectContext) -> Bool {
        !pins(day: c.dayKey, feastID: c.entry.id, context: context).isEmpty
    }

    @MainActor
    static func pin(_ c: Celebration, persistence: Persistence) {
        guard !isPinned(c, context: persistence.context) else { return }
        let p = persistence.insert(CDFeastPin.self)
        p.id = UUID()
        p.day = c.dayKey
        p.feastID = c.entry.id
        p.title = c.entry.name
        p.createdAt = Date()
        p.household = persistence.household()
        persistence.save()
    }

    @MainActor
    static func unpin(_ c: Celebration, persistence: Persistence) {
        pins(day: c.dayKey, feastID: c.entry.id, context: persistence.context).forEach(persistence.context.delete)
        persistence.save()
    }
}

/// A pinned feast as plain values, so the overlay logic doesn't touch Core Data.
struct PinnedFeast: Hashable, Sendable {
    var day: String
    var feastID: String
    var title: String
}

extension CDFeastPin {
    var value: PinnedFeast? {
        guard let day, let feastID else { return nil }
        return PinnedFeast(day: day, feastID: feastID, title: title ?? "")
    }
}
