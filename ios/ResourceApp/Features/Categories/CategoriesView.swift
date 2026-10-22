import SwiftUI

@MainActor
final class CategoriesViewModel: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = categories.isEmpty
        error = nil

        do {
            categories = try await APIClient.shared.get("/api/categories")
        } catch let apiError as APIError {
            if !apiError.isCancelled {
                error = apiError.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

struct CategoriesView: View {
    @StateObject private var viewModel = CategoriesViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.isLoading && viewModel.categories.isEmpty {
                    LoadingRowsView(count: 4)
                } else if let error = viewModel.error, viewModel.categories.isEmpty {
                    ErrorStateView(message: error) {
                        Task { await viewModel.load() }
                    }
                } else if viewModel.categories.isEmpty {
                    EmptyStateView(
                        icon: "square.grid.2x2",
                        title: "暂无分类",
                        message: "后台还没有创建分类，或分类数据尚未同步。"
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.categories) { category in
                            NavigationLink {
                                CategoryAppsView(
                                    mainSlug: category.slug,
                                    title: category.name,
                                    initialCategory: category
                                )
                            } label: {
                                CategoryCard(category: category)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    subcategorySection
                }
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("分类")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load()
        }
        .task {
            if viewModel.categories.isEmpty {
                await viewModel.load()
            }
        }
    }

    private var subcategorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "全部分类", subtitle: "按类型快速筛选")

            ForEach(viewModel.categories) { category in
                if !category.children.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(category.children) { child in
                                NavigationLink {
                                    CategoryAppsView(
                                        mainSlug: category.slug,
                                        title: child.name,
                                        initialCategory: category,
                                        initialChildID: child.id
                                    )
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(child.name)
                                            .lineLimit(1)

                                        if child.appsCount > 0 {
                                            Text("\(child.appsCount)")
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .frame(maxWidth: .infinity)
                                    .background(Theme.cardBackground)
                                    .foregroundStyle(.primary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CategoryCard: View {
    let category: Category

    private var tint: Color {
        if category.name.contains("游戏") {
            return Theme.purple
        }

        if category.name.contains("巨魔") {
            return Theme.pink
        }

        return Theme.accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .frame(width: 42, height: 42)

                    Image(systemName: category.categoryIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }

                Spacer()

                Text("\(category.appsCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(category.name)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(category.children.isEmpty ? "查看全部资源" : "\(category.children.count) 个子分类")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !category.children.isEmpty {
                Text(category.children.prefix(3).map(\.name).joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.10), lineWidth: 1)
        )
    }
}

struct CategoryAppsView: View {
    let mainSlug: String
    let title: String

    @StateObject private var viewModel: AppListViewModel
    @State private var children: [Category]
    @State private var selectedChildID: Int?
    @State private var query = ""

    init(
        mainSlug: String,
        title: String,
        initialCategory: Category? = nil,
        initialChildID: Int? = nil
    ) {
        self.mainSlug = mainSlug
        self.title = title
        _viewModel = StateObject(
            wrappedValue: AppListViewModel(mainSlug: mainSlug, categoryID: initialChildID)
        )
        _children = State(initialValue: initialCategory?.children ?? [])
        _selectedChildID = State(initialValue: initialChildID)
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $query, placeholder: "搜索\(title)")
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !children.isEmpty {
                        chipBar
                    }

                    HStack(spacing: 8) {
                        Text(query.trimmed.isEmpty ? "\(viewModel.total) 个资源" : "找到 \(viewModel.total) 个结果")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Menu {
                            Button("最新更新") { changeSort("latest") }
                            Button("最多浏览") { changeSort("popular") }
                            Button("积分从高到低") { changeSort("points") }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(sortTitle)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                        }
                    }

                    if viewModel.isLoading && viewModel.items.isEmpty {
                        LoadingRowsView()
                    } else if let error = viewModel.error, viewModel.items.isEmpty {
                        ErrorStateView(message: error) {
                            Task { await viewModel.reload() }
                        }
                    } else if viewModel.items.isEmpty {
                        EmptyStateView(
                            icon: query.trimmed.isEmpty ? "tray" : "magnifyingglass",
                            title: query.trimmed.isEmpty ? "这个分类还没有资源" : "没有找到相关资源",
                            message: query.trimmed.isEmpty ? "换个分类看看，或稍后再来。" : "试试更短的关键词，或切换到其他分类。"
                        )
                    } else {
                        ForEach(viewModel.items) { app in
                            NavigationLink {
                                AppDetailView(app: app)
                            } label: {
                                AppRow(app: app)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if app.id == viewModel.items.last?.id {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                    }
                }
                .padding(16)
            }
            .refreshable {
                await viewModel.reload()
            }
        }
        .background(Theme.groupedBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: query) {
            let keyword = query.trimmed

            if !keyword.isEmpty {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
            }

            viewModel.setKeyword(keyword)
            await viewModel.reload()
        }
        .task {
            if children.isEmpty {
                await loadChildren()
            }
        }
    }

    private var sortTitle: String {
        switch viewModel.sort {
        case "popular":
            return "最多浏览"
        case "points":
            return "积分优先"
        default:
            return "最新更新"
        }
    }

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", isSelected: selectedChildID == nil) {
                    selectChild(nil)
                }

                ForEach(children) { child in
                    chip(title: child.name, isSelected: selectedChildID == child.id) {
                        selectChild(child.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Theme.accent : Theme.cardBackground)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func selectChild(_ id: Int?) {
        guard selectedChildID != id else { return }
        selectedChildID = id
        viewModel.setCategory(id)

        Task {
            await viewModel.reload()
        }
    }

    private func changeSort(_ sort: String) {
        guard viewModel.sort != sort else { return }
        viewModel.sort = sort

        Task {
            await viewModel.reload()
        }
    }

    private func loadChildren() async {
        do {
            let all: [Category] = try await APIClient.shared.get("/api/categories")

            if let category = all.first(where: { $0.slug == mainSlug }) {
                children = category.children
            }
        } catch {
            // 子分类加载失败不影响主列表
        }
    }
}
