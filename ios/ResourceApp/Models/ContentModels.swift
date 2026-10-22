import Foundation

struct AuthResponse: Decodable {
    let token: String
    let tokenExpiresAt: String?
    let user: User

    enum CodingKeys: String, CodingKey {
        case token
        case tokenExpiresAt = "token_expires_at"
        case user
    }
}

struct ArticleRef: Decodable, Hashable {
    let id: Int
    let title: String
}

struct Article: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let summary: String?
    let cover: String?
    let content: String?
    let views: Int
    let publishedAt: String?
    let createdAt: String?
    let prev: ArticleRef?
    let next: ArticleRef?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case cover
        case content
        case views
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case prev
        case next
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名文章"
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        views = try container.decodeIfPresent(Int.self, forKey: .views) ?? 0
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        prev = try container.decodeIfPresent(ArticleRef.self, forKey: .prev)
        next = try container.decodeIfPresent(ArticleRef.self, forKey: .next)
    }
}

struct Message: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let body: String?
    let url: String?
    let color: String?
    let isRead: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case url
        case color
        case isRead = "is_read"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else {
            id = String(try container.decode(Int.self, forKey: .id))
        }

        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "系统通知"
        body = try container.decodeIfPresent(String.self, forKey: .body)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct MessagePage: Decodable {
    let items: [Message]
    let page: Int
    let total: Int
    let hasMore: Bool
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case items
        case page
        case total
        case hasMore = "has_more"
        case unreadCount = "unread_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        items = try container.decodeIfPresent([Message].self, forKey: .items) ?? []
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }
}

struct SignInResult: Decodable {
    let pointsGained: Int
    let continuousDays: Int
    let user: User

    enum CodingKeys: String, CodingKey {
        case pointsGained = "points_gained"
        case continuousDays = "continuous_days"
        case user
    }
}

struct PointLog: Decodable, Identifiable, Hashable {
    let id: Int
    let type: String
    let action: Int
    let points: Int
    let beforePoints: Int
    let afterPoints: Int
    let description: String
    let createdAt: String?

    var isIncrease: Bool { action == 1 }
    var signedPoints: String { (isIncrease ? "+" : "-") + "\(abs(points))" }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case action
        case points
        case beforePoints = "before_points"
        case afterPoints = "after_points"
        case description
        case createdAt = "created_at"
    }
}

struct PointPage: Decodable {
    let items: [PointLog]
    let page: Int
    let hasMore: Bool
    let currentPoints: Int

    enum CodingKeys: String, CodingKey {
        case items
        case page
        case hasMore = "has_more"
        case currentPoints = "current_points"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        items = try container.decodeIfPresent([PointLog].self, forKey: .items) ?? []
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        currentPoints = try container.decodeIfPresent(Int.self, forKey: .currentPoints) ?? 0
    }
}

struct DownloadRecord: Decodable, Identifiable, Hashable {
    let id: Int
    let appID: Int
    let appName: String
    let appIcon: String?
    let appVersion: String
    let appSize: String
    let pointsSpent: Int
    let downloadType: String
    let downloadTypeLabel: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case appID = "app_id"
        case appName = "app_name"
        case appIcon = "app_icon"
        case appVersion = "app_version"
        case appSize = "app_size"
        case pointsSpent = "points_spent"
        case downloadType = "download_type"
        case downloadTypeLabel = "download_type_label"
        case createdAt = "created_at"
    }
}

struct DownloadPage: Decodable {
    let items: [DownloadRecord]
    let page: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case page
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        items = try container.decodeIfPresent([DownloadRecord].self, forKey: .items) ?? []
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}
