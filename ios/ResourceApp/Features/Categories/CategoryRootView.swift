import SwiftUI

/// 底部三个资源标签页的根视图：
/// 先按分类名称（应用 / 游戏 / 巨魔）找到站点上的主分类，再展示分类资源列表。
struct CategoryRootView: View {
    let title: String
    let categoryName: String
    let fallbackSlug: String

    @State private var category: Category?
    @State private var isLoading = false
    @State private var error: String?

    init(title: String, categoryName: String, fallbackSlug: String) {
        self.title = title
        self.categoryName = categoryName
        self.fallbackSlug = fallbackSlug
    }

    var body: some View {
        Group {
            if let category {
                CategoryAppsView(
                    mainSlug: category.slug,
                    title: title,
                    initialCategory: category
                )
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载\(title)分类")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.groupedBackground)
            } else {
                ScrollView {
                    ErrorStateView(message: error ?? "分类加载失败") {
                        Task { await load() }
                    }
                    .padding(.top, 60)
                }
                .background(Theme.groupedBackground)
            }
        }
        .task {
            if category == nil, !isLoading {
                await load()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let all: [Category] = try await APIClient.shared.get("/api/categories")

            if let match = all.first(where: { $0.name == categoryName })
                ?? all.first(where: { $0.slug == fallbackSlug }) {
                category = match
            } else {
                error = "服务器上还没有「\(categoryName)」分类"
            }
        } catch {
            self.error = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
