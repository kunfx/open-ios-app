import Foundation

@MainActor
final class AppListViewModel: ObservableObject {
    @Published private(set) var items: [AppItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var total = 0
    @Published var error: String?

    var sort: String = "latest"

    let mainSlug: String?

    private(set) var categoryID: Int?
    private var keyword: String?
    private var page = 1
    private var hasMore = true
    private var hasLoaded = false
    private var requestID = UUID()

    init(mainSlug: String? = nil, categoryID: Int? = nil, keyword: String? = nil) {
        self.mainSlug = mainSlug
        self.categoryID = categoryID
        self.keyword = keyword?.trimmed
    }

    func setCategory(_ id: Int?) {
        categoryID = id
    }

    func setKeyword(_ value: String?) {
        let trimmed = value?.trimmed
        keyword = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    func clear() {
        requestID = UUID()
        items = []
        total = 0
        error = nil
        page = 1
        hasMore = true
        hasLoaded = false
        keyword = nil
        isLoading = false
        isLoadingMore = false
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        let currentRequest = UUID()
        requestID = currentRequest
        hasLoaded = true
        isLoading = true
        error = nil

        do {
            let result: Page<AppItem> = try await APIClient.shared.get(
                "/api/apps",
                query: query(page: 1)
            )

            guard requestID == currentRequest else { return }

            items = result.items
            total = result.total
            page = 1
            hasMore = result.hasMore
        } catch {
            guard requestID == currentRequest else { return }
            handle(error)
        }

        if requestID == currentRequest {
            isLoading = false
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }

        let currentRequest = requestID
        isLoadingMore = true
        let nextPage = page + 1

        do {
            let result: Page<AppItem> = try await APIClient.shared.get(
                "/api/apps",
                query: query(page: nextPage)
            )

            guard requestID == currentRequest else { return }

            items.append(contentsOf: result.items)
            total = result.total
            page = nextPage
            hasMore = result.hasMore
        } catch {
            guard requestID == currentRequest else { return }
            handle(error)
        }

        if requestID == currentRequest {
            isLoadingMore = false
        }
    }

    private func query(page: Int) -> [String: String] {
        var query: [String: String] = [
            "page": "\(page)",
            "per_page": "20",
            "sort": sort,
        ]

        if let mainSlug, !mainSlug.isEmpty {
            query["main"] = mainSlug
        }

        if let categoryID {
            query["category_id"] = "\(categoryID)"
        }

        if let keyword, !keyword.isEmpty {
            query["q"] = keyword
        }

        return query
    }

    private func handle(_ error: Error) {
        if let apiError = error as? APIError, apiError.isCancelled {
            return
        }

        self.error = (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}
