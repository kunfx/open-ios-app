import SwiftUI

@MainActor
final class ArticlesViewModel: ObservableObject {
    @Published private(set) var items: [Article] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var error: String?

    private var page = 1
    private var hasMore = true
    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = items.isEmpty
        error = nil
        hasLoaded = true

        do {
            let result: Page<Article> = try await APIClient.shared.get(
                "/api/articles",
                query: ["page": "1", "per_page": "15"]
            )

            items = result.items
            page = 1
            hasMore = result.hasMore
        } catch let apiError as APIError {
            if !apiError.isCancelled {
                error = apiError.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }

        isLoadingMore = true
        let nextPage = page + 1

        do {
            let result: Page<Article> = try await APIClient.shared.get(
                "/api/articles",
                query: ["page": "\(nextPage)", "per_page": "15"]
            )

            items.append(contentsOf: result.items)
            page = nextPage
            hasMore = result.hasMore
        } catch {
            // 滚动到底部可重试
        }

        isLoadingMore = false
    }
}

struct ArticlesView: View {
    @StateObject private var viewModel = ArticlesViewModel()
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if viewModel.isLoading {
                    LoadingRowsView(count: 5)
                } else if let error = viewModel.error, viewModel.items.isEmpty {
                    ErrorStateView(message: error) {
                        Task { await viewModel.reload() }
                    }
                } else if viewModel.items.isEmpty {
                    EmptyStateView(
                        icon: "book",
                        title: "暂无教程文章",
                        message: "后台发布文章后会显示在这里。"
                    )
                } else {
                    ForEach(viewModel.items) { article in
                        NavigationLink {
                            ArticleDetailView(article: article)
                        } label: {
                            ArticleRow(article: article)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if article.id == viewModel.items.last?.id {
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
        .background(Theme.groupedBackground)
        .navigationTitle("教程文章")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.reload()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

@MainActor
final class ArticleDetailViewModel: ObservableObject {
    @Published private(set) var article: Article
    @Published private(set) var isLoading = false
    @Published var error: String?

    init(article: Article) {
        self.article = article
    }

    func load() async {
        isLoading = article.content == nil
        error = nil

        do {
            article = try await APIClient.shared.get("/api/articles/\(article.id)")
        } catch let apiError as APIError {
            if !apiError.isCancelled, article.content == nil {
                error = apiError.localizedDescription
            }
        } catch {
            if article.content == nil {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }
}

struct ArticleDetailView: View {
    @StateObject private var viewModel: ArticleDetailViewModel

    init(article: Article) {
        _viewModel = StateObject(wrappedValue: ArticleDetailViewModel(article: article))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                VStack {
                    Spacer()
                    ErrorStateView(message: error) {
                        Task { await viewModel.load() }
                    }
                    Spacer()
                }
            } else if let content = viewModel.article.content, !content.isEmpty {
                HTMLContentView(html: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    EmptyStateView(
                        icon: "doc.text",
                        title: "暂无正文",
                        message: "这篇文章还没有可显示的内容。"
                    )
                    Spacer()
                }
            }
        }
        .background(Theme.groupedBackground)
        .navigationTitle("文章")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(viewModel.article.title)
                .font(.headline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(DateText.day(viewModel.article.publishedAt ?? viewModel.article.createdAt))

                Text("·")

                Image(systemName: "eye")
                Text("\(viewModel.article.views)")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
    }
}

struct ArticleRow: View {
    let article: Article

    var body: some View {
        HStack(spacing: 12) {
            if let cover = article.cover, !cover.isEmpty {
                RemoteImage(urlString: cover)
                    .frame(width: 92, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let summary = article.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(DateText.day(article.publishedAt ?? article.createdAt))
                    Text("·")
                    Image(systemName: "eye")
                    Text("\(article.views)")
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(11)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
