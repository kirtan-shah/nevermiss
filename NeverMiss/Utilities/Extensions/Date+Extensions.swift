import Foundation

extension Date {

    // MARK: - Static Properties

    static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    static var endOfToday: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!
    }

    static var startOfTomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!
    }

    // MARK: - Instance Properties

    var isInCurrentHour: Bool {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .hour)
    }

    var meetingTimeFormat: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    var relativeFormat: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    // MARK: - Methods

    func isWithinNext(minutes: Int) -> Bool {
        let now = Date()
        let futureDate = now.addingTimeInterval(TimeInterval(minutes * 60))
        return self >= now && self <= futureDate
    }
}
