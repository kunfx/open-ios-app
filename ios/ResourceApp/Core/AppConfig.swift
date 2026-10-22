import Foundation

/// 服务器地址配置：默认指向你的资源站，用户可在「我的 → 服务器设置」中修改。
final class AppConfig {
    static let shared = AppConfig()

    static let defaultBaseURLString = "https://ifeng.app"

    private let defaults = UserDefaults.standard
    private let baseURLKey = "api.baseURL"

    private init() {
        if defaults.string(forKey: baseURLKey) == nil {
            defaults.set(Self.defaultBaseURLString, forKey: baseURLKey)
        }
    }

    var baseURLString: String {
        get { defaults.string(forKey: baseURLKey) ?? Self.defaultBaseURLString }
        set { defaults.set(Self.normalize(newValue), forKey: baseURLKey) }
    }

    var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: Self.defaultBaseURLString)!
    }

    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.isEmpty {
            return defaultBaseURLString
        }

        let lower = value.lowercased()

        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            value = "https://" + value
        }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        return value
    }

    /// 把接口里的相对路径（例如 /app-icons/a.png、/api/download/...）补全成绝对地址。
    func absoluteURL(from path: String?) -> URL? {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let value = path.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: value), url.scheme != nil {
            return url
        }

        let base = baseURLString

        if value.hasPrefix("/") {
            return URL(string: base + value)
        }

        return URL(string: base + "/" + value)
    }
}
