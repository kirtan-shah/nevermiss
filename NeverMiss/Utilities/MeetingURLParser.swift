import Foundation

// MARK: - MeetingURLParser

struct MeetingURLParser {

    // MARK: - Types

    /// Supported meeting platforms
    enum MeetingPlatform: String, CaseIterable {
        case googleMeet = "Google Meet"
        case zoom = "Zoom"
        case microsoftTeams = "Microsoft Teams"
        case webex = "WebEx"
        case gotoMeeting = "GoToMeeting"
        case whereby = "Whereby"
        case around = "Around"
        case unknown = "Video Call"

        var iconName: String {
            switch self {
            case .googleMeet: return "video.fill"
            case .zoom: return "video.fill"
            case .microsoftTeams: return "video.fill"
            case .webex: return "video.fill"
            case .gotoMeeting: return "video.fill"
            case .whereby: return "video.fill"
            case .around: return "video.fill"
            case .unknown: return "video.fill"
            }
        }
    }

    // MARK: - Properties

    /// Known meeting URL patterns
    private static let platformPatterns: [(platform: MeetingPlatform, patterns: [String])] = [
        (.googleMeet, ["meet.google.com"]),
        (.zoom, ["zoom.us", "zoom.com", "zoomgov.com"]),
        (.microsoftTeams, ["teams.microsoft.com", "teams.live.com"]),
        (.webex, ["webex.com"]),
        (.gotoMeeting, ["gotomeeting.com", "goto.com"]),
        (.whereby, ["whereby.com"]),
        (.around, ["around.co"])
    ]

    // MARK: - Methods

    static func extractMeetingURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = detector.matches(in: text, options: [], range: range)

        for match in matches {
            guard let urlRange = Range(match.range, in: text) else { continue }
            let urlString = String(text[urlRange])

            if let url = URL(string: urlString), isMeetingURL(urlString) {
                return url
            }
        }

        return nil
    }

    static func isMeetingURL(_ urlString: String) -> Bool {
        let lowercased = urlString.lowercased()
        return platformPatterns.contains { _, patterns in
            patterns.contains { lowercased.contains($0) }
        }
    }

    static func identifyPlatform(from url: URL) -> MeetingPlatform {
        let urlString = url.absoluteString.lowercased()

        for (platform, patterns) in platformPatterns {
            if patterns.contains(where: { urlString.contains($0) }) {
                return platform
            }
        }

        return .unknown
    }

    static func identifyPlatform(from urlString: String) -> MeetingPlatform {
        let lowercased = urlString.lowercased()

        for (platform, patterns) in platformPatterns {
            if patterns.contains(where: { lowercased.contains($0) }) {
                return platform
            }
        }

        return .unknown
    }

    static func extractAllMeetingURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = detector.matches(in: text, options: [], range: range)

        return matches.compactMap { match in
            guard let urlRange = Range(match.range, in: text) else { return nil }
            let urlString = String(text[urlRange])

            if let url = URL(string: urlString), isMeetingURL(urlString) {
                return url
            }
            return nil
        }
    }
}
