import SwiftUI

@MainActor
final class PointsViewModel: ObservableObject {
    @Published private(set) var items: [PointLog] = []
    @Published private(set) var currentPoints = 0
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
            let result: PointPage = try await APIClient.shared.get(
                "/api/user/points",
                query: ["page": "1", "per_page": "30"]
            )

            items = result.items
            currentPoints = result.currentPoints
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
            let result: PointPage = try await APIClient.shared.get(
                "/api/user/points",
                query: ["page": "\(nextPage)", "per_page": "30"]
            )

            items.append(contentsOf: result.items)
            currentPoints = result.currentPoints
            page = nextPage
            hasMore = result.hasMore
        } catch {
            // 滚动到底部可重试
        }

        isLoadingMore = false
    }
}

struct PointsView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel = PointsViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                pointsHeader

                if viewModel.isLoading {
                    LoadingRowsView(count: 5)
                } else if let error = viewModel.error, viewModel.items.isEmpty {
                    ErrorStateView(message: error) {
                        Task { await viewModel.reload() }
                    }
                } else if viewModel.items.isEmpty {
                    EmptyStateView(
                        icon: "list.bullet.rectangle",
                        title: "暂无积分记录",
                        message: "签到、下载、兑换会员等操作都会记录在这里。"
                    )
                } else {
                    ForEach(viewModel.items) { log in
                        PointLogRow(log: log)
                            .onAppear {
                                if log.id == viewModel.items.last?.id {
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
        .navigationTitle("积分明细")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.reload()
            await session.refreshProfile()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private var pointsHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.gold.opacity(0.14))
                    .frame(width: 46, height: 46)

                Image(systemName: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("当前积分")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(viewModel.currentPoints)")
                    .font(.title2.weight(.black))
                    .foregroundStyle(Theme.gold)
            }

            Spacer()

            Text("积分可用于下载资源")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PointLogRow: View {
    let log: PointLog

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((log.isIncrease ? Theme.accent : Theme.pink).opacity(0.12))
                    .frame(width: 36, height: 36)

                Image(systemName: log.isIncrease ? "plus" : "minus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(log.isIncrease ? Theme.accent : Theme.pink)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(log.description.isEmpty ? log.type : log.description)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(DateText.dateTime(log.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(log.signedPoints)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(log.isIncrease ? Theme.accent : Theme.pink)
        }
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
