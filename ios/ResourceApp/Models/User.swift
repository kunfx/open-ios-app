import Foundation

struct User: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let email: String
    let avatar: String?
    let points: Int
    let vipLevel: Int
    let vipLevelText: String
    let vipActive: Bool
    let vipExpiredAt: String?
    let vipExpiredText: String
    let isAdmin: Bool
    let createdAt: String?
    let freeLimitToday: Int
    let freeUsedToday: Int
    let freeLeftToday: Int
    let unlimitedDownloads: Bool
    let signedToday: Bool
    let unreadMessages: Int
    let mustChangePassword: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case avatar
        case points
        case vipLevel = "vip_level"
        case vipLevelText = "vip_level_text"
        case vipActive = "vip_active"
        case vipExpiredAt = "vip_expired_at"
        case vipExpiredText = "vip_expired_text"
        case isAdmin = "is_admin"
        case createdAt = "created_at"
        case freeLimitToday = "free_limit_today"
        case freeUsedToday = "free_used_today"
        case freeLeftToday = "free_left_today"
        case unlimitedDownloads = "unlimited_downloads"
        case signedToday = "signed_today"
        case unreadMessages = "unread_messages"
        case mustChangePassword = "must_change_password"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "用户"
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        points = try container.decodeIfPresent(Int.self, forKey: .points) ?? 0
        vipLevel = try container.decodeIfPresent(Int.self, forKey: .vipLevel) ?? 0
        vipLevelText = try container.decodeIfPresent(String.self, forKey: .vipLevelText) ?? "免费用户"
        vipActive = try container.decodeIfPresent(Bool.self, forKey: .vipActive) ?? false
        vipExpiredAt = try container.decodeIfPresent(String.self, forKey: .vipExpiredAt)
        vipExpiredText = try container.decodeIfPresent(String.self, forKey: .vipExpiredText) ?? "非会员"
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        freeLimitToday = try container.decodeIfPresent(Int.self, forKey: .freeLimitToday) ?? 0
        freeUsedToday = try container.decodeIfPresent(Int.self, forKey: .freeUsedToday) ?? 0
        freeLeftToday = try container.decodeIfPresent(Int.self, forKey: .freeLeftToday) ?? 0
        unlimitedDownloads = try container.decodeIfPresent(Bool.self, forKey: .unlimitedDownloads) ?? false
        signedToday = try container.decodeIfPresent(Bool.self, forKey: .signedToday) ?? false
        unreadMessages = try container.decodeIfPresent(Int.self, forKey: .unreadMessages) ?? 0
        mustChangePassword = try container.decodeIfPresent(Bool.self, forKey: .mustChangePassword) ?? false
    }

    var freeLeftText: String {
        if unlimitedDownloads || freeLeftToday < 0 {
            return "不限"
        }

        return "\(max(0, freeLeftToday))"
    }

    var badgeText: String {
        if isAdmin {
            return "管理员"
        }

        return vipActive ? vipLevelText : "免费用户"
    }
}
