import Foundation

struct DateFormatters {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let displayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    static let displayDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter
    }()

    static func formatDisplayDate(_ date: Date) -> String {
        displayDate.string(from: date)
    }

    static func formatDisplayDateTime(_ date: Date) -> String {
        displayDateTime.string(from: date)
    }

    static func parseISO8601(_ string: String) -> Date? {
        iso8601.date(from: string)
    }

    static func formatISO8601(_ date: Date) -> String {
        iso8601.string(from: date)
    }
}
