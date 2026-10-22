import SwiftUI

@MainActor
final class DownloadHistoryViewModel: ObservableObject {
    @Published private(set) var items: [DownloadRecord] = []
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
            let result: DownloadPage = try await APIClient.shared.get(
                "/api/user/downloads",
                query: ["page": "1", "per_page": "20"]
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
            let result: DownloadPage = try await APIClient.shared.get(
                "/api/user/downloads",
                query: ["page": "\(nextPage)", "per_page": "20"]
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

struct DownloadHistoryView: View {
    @StateObject private var viewModel = DownloadHistoryViewModel()

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
                        icon: "arrow.down.circle",
                        title: "暂无下载记录",
                        message: "去「应用 / 游戏 / 巨魔」挑一个喜欢的资源吧。"
                    )
                } else {
                    ForEach(viewModel.items) { record in
                        NavigationLink {
                            AppDetailView(appID: record.appID)
                        } label: {
                            DownloadRecordRow(record: record)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if record.id == viewModel.items.last?.id {
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
        .navigationTitle("下载记录")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.reload()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }
}

struct DownloadRecordRow: View {
    let record: DownloadRecord

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(urlString: record.appIcon, size: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.appName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("v\(record.appVersion) · \(record.appSize)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(DateText.dateTime(record.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                Text(record.downloadTypeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.12))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())

                if record.pointsSpent > 0 {
                    Text("-\(record.pointsSpent) 积分")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.gold)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
