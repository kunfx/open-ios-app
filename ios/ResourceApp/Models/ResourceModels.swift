import Foundation

struct Page<T: Decodable>: Decodable {
    let items: [T]
    let page: Int
    let perPage: Int
    let total: Int
    let lastPage: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case page
        case perPage = "per_page"
        case total
        case lastPage = "last_page"
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedItems = try container.decodeIfPresent([T].self, forKey: .items) ?? []
        items = decodedItems
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        perPage = try container.decodeIfPresent(Int.self, forKey: .perPage) ?? decodedItems.count
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? decodedItems.count
        lastPage = try container.decodeIfPresent(Int.self, forKey: .lastPage) ?? 1
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

struct CategoryRef: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let slug: String
}

struct Category: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let parentID: Int?
    let appsCount: Int
    let children: [Category]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case parentID = "parent_id"
        case appsCount = "apps_count"
        case children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名"
        slug = try container.decodeIfPresent(String.self, forKey: .slug) ?? ""
        parentID = try container.decodeIfPresent(Int.self, forKey: .parentID)
        appsCount = try container.decodeIfPresent(Int.self, forKey: .appsCount) ?? 0
        children = try container.decodeIfPresent([Category].self, forKey: .children) ?? []
    }

    var categoryIcon: String {
        if name.contains("游戏") {
            return "gamecontroller.fill"
        }

        if name.contains("巨魔") {
            return "wrench.and.screwdriver.fill"
        }

        if name.contains("应用") {
            return "square.grid.2x2.fill"
        }

        return "folder.fill"
    }
}

struct AppItem: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let nameEn: String?
    let icon: String?
    let version: String
    let size: String
    let pointsRequired: Int
    let shortDescription: String?
    let descriptionHTML: String?
    let modInfo: String?
    let screenshots: [String]
    let downloadLinks: [DownloadLinkInfo]
    let views: Int
    let category: CategoryRef?
    let mainCategory: CategoryRef?
    let updatedAt: String?
    var unlocked: Bool

    var isFree: Bool { pointsRequired <= 0 }

    var subtitle: String {
        "v\(version) · \(size)"
    }

    var plainDescription: String {
        (descriptionHTML ?? shortDescription ?? "").htmlToPlainText
    }

    var modLines: [String] {
        (modInfo ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameEn = "name_en"
        case icon
        case version
        case size
        case pointsRequired = "points_required"
        case shortDescription = "short_description"
        case descriptionHTML = "description"
        case modInfo = "mod_info"
        case screenshots
        case downloadLinks = "download_links"
        case views
        case category
        case mainCategory = "main_category"
        case updatedAt = "updated_at"
        case unlocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名资源"
        nameEn = try container.decodeIfPresent(String.self, forKey: .nameEn)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        size = try container.decodeIfPresent(String.self, forKey: .size) ?? "未知大小"
        pointsRequired = try container.decodeIfPresent(Int.self, forKey: .pointsRequired) ?? 0
        shortDescription = try container.decodeIfPresent(String.self, forKey: .shortDescription)
        descriptionHTML = try container.decodeIfPresent(String.self, forKey: .descriptionHTML)
        modInfo = try container.decodeIfPresent(String.self, forKey: .modInfo)
        screenshots = try container.decodeIfPresent([String].self, forKey: .screenshots) ?? []
        downloadLinks = try container.decodeIfPresent([DownloadLinkInfo].self, forKey: .downloadLinks) ?? []
        views = try container.decodeIfPresent(Int.self, forKey: .views) ?? 0
        category = try container.decodeIfPresent(CategoryRef.self, forKey: .category)
        mainCategory = try container.decodeIfPresent(CategoryRef.self, forKey: .mainCategory)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        unlocked = try container.decodeIfPresent(Bool.self, forKey: .unlocked) ?? false
    }
}

struct DownloadLinkInfo: Decodable, Hashable, Identifiable {
    let title: String
    let linkType: String?
    let remark: String?

    var id: String { title + "|" + (linkType ?? "") + "|" + (remark ?? "") }

    enum CodingKeys: String, CodingKey {
        case title
        case linkType = "type"
        case remark
    }
}

struct DownloadLink: Decodable, Identifiable, Hashable {
    let title: String
    let linkType: String?
    let remark: String?
    let path: String?
    let url: String?

    var id: String { title + "|" + (path ?? url ?? "") }

    enum CodingKeys: String, CodingKey {
        case title
        case linkType = "type"
        case remark
        case path
        case url
    }
}

struct DownloadResult: Decodable, Identifiable {
    let id = UUID()
    let status: String?
    let message: String?
    let costType: String?
    let pointsRequired: Int?
    let pointsSpent: Int?
    let userPoints: Int?
    let downloadLinks: [DownloadLink]

    enum CodingKeys: String, CodingKey {
        case status
        case message
        case costType = "cost_type"
        case pointsRequired = "points_required"
        case pointsSpent = "points_spent"
        case userPoints = "user_points"
        case downloadLinks = "download_links"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        status = try container.decodeIfPresent(String.self, forKey: .status)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        costType = try container.decodeIfPresent(String.self, forKey: .costType)
        pointsRequired = try container.decodeIfPresent(Int.self, forKey: .pointsRequired)
        pointsSpent = try container.decodeIfPresent(Int.self, forKey: .pointsSpent)
        userPoints = try container.decodeIfPresent(Int.self, forKey: .userPoints)
        downloadLinks = try container.decodeIfPresent([DownloadLink].self, forKey: .downloadLinks) ?? []
    }
}

struct HomeResponse: Decodable {
    let featured: [AppItem]
    let apps: [AppItem]
    let games: [AppItem]
    let trolls: [AppItem]
    let articles: [Article]
    let categories: [Category]

    enum CodingKeys: String, CodingKey {
        case featured
        case apps
        case games
        case trolls
        case articles
        case categories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        featured = try container.decodeIfPresent([AppItem].self, forKey: .featured) ?? []
        apps = try container.decodeIfPresent([AppItem].self, forKey: .apps) ?? []
        games = try container.decodeIfPresent([AppItem].self, forKey: .games) ?? []
        trolls = try container.decodeIfPresent([AppItem].self, forKey: .trolls) ?? []
        articles = try container.decodeIfPresent([Article].self, forKey: .articles) ?? []
        categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? []
    }
}
