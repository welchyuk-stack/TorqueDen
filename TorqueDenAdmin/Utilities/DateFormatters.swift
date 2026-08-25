import Foundation

enum DateFormatters {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static let absolute: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func string(from date: Date) -> String {
        let interval = -date.timeIntervalSinceNow
        if interval < 86400 {
            return relative.localizedString(for: date, relativeTo: Date())
        }
        return absolute.string(from: date)
    }
}
