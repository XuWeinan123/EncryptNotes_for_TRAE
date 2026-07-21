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

    private static let hourMinute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let monthDayHourMinute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static let yearMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func formatDisplayDate(_ date: Date) -> String {
        displayDate.string(from: date)
    }

    static func formatDisplayDateTime(_ date: Date) -> String {
        displayDateTime.string(from: date)
    }

    static func formatNoteListRelativeTime(_ date: Date, relativeTo now: Date = Date(), calendar: Calendar = .current) -> String {
        let diff = max(0, now.timeIntervalSince(date))

        if diff < 60 {
            return "刚刚"
        }

        if diff < 3600 {
            return "\(Int(floor(diff / 60))) 分钟前"
        }

        if diff < 86400 {
            return hourMinute.string(from: date)
        }

        if diff < 2 * 86400 {
            return "昨天 \(hourMinute.string(from: date))"
        }

        if diff < 7 * 86400 {
            return "\(Int(floor(diff / 86400))) 天前 \(hourMinute.string(from: date))"
        }

        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return monthDayHourMinute.string(from: date)
        }

        return yearMonthDay.string(from: date)
    }

    static func parseISO8601(_ string: String) -> Date? {
        iso8601.date(from: string)
    }

    static func formatISO8601(_ date: Date) -> String {
        iso8601.string(from: date)
    }
}
