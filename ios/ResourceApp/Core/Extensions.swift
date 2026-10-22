import Foundation

enum DateText {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }

        if let date = withFractional.date(from: iso) {
            return date
        }

        return plain.date(from: iso)
    }

    /// "3 分钟前 / 昨天 / 2026-10-01"
    static func relative(_ iso: String?) -> String {
        guard let date = date(from: iso) else {
            return ""
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short

        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// "2026-10-01"
    static func day(_ iso: String?) -> String {
        guard let date = date(from: iso) else {
            return String((iso ?? "").prefix(10))
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter.string(from: date)
    }

    /// "2026-10-01 18:30"
    static func dateTime(_ iso: String?) -> String {
        guard let date = date(from: iso) else {
            return String((iso ?? "").prefix(16))
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        return formatter.string(from: date)
    }
}

extension String {
    /// 把后台富文本描述转成 SwiftUI Text 可显示的纯文本。
    var htmlToPlainText: String {
        var text = self

        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</li\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let entities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&mdash;": "—",
        ]

        for (key, value) in entities {
            text = text.replacingOccurrences(of: key, with: value)
        }

        return text
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
