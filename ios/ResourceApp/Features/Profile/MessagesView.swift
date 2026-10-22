import SwiftUI

struct UnreadCountResponse: Decodable {
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case unreadCount = "unread_count"
    }
}

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published private(set) var items: [Message] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var locallyReadIDs: Set<String> = []
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
            let result: MessagePage = try await APIClient.shared.get(
                "/api/messages",
                query: ["page": "1", "per_page": "20"]
            )

            items = result.items
            unreadCount = result.unreadCount
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
            let result: MessagePage = try await APIClient.shared.get(
                "/api/messages",
                query: ["page": "\(nextPage)", "per_page": "20"]
            )

            items.append(contentsOf: result.items)
            unreadCount = result.unreadCount
            page = nextPage
            hasMore = result.hasMore
        } catch {
            // 静默失败，滚动到底部可重试
        }

        isLoadingMore = false
    }

    func isUnread(_ message: Message) -> Bool {
        !message.isRead && !locallyReadIDs.contains(message.id)
    }

    func markRead(_ message: Message) async {
        guard isUnread(message) else { return }

        locallyReadIDs.insert(message.id)
        unreadCount = max(0, unreadCount - 1)

        do {
            let response: UnreadCountResponse = try await APIClient.shared.post(
                "/api/messages/\(message.id)/read"
            )
            unreadCount = response.unreadCount
        } catch {
            // 即使请求失败也保留已读状态，下次刷新会以服务器为准
        }
    }

    func markAllRead() async {
        guard unreadCount > 0 else { return }

        locallyReadIDs = Set(items.map(\.id))
        unreadCount = 0

        do {
            let response: UnreadCountResponse = try await APIClient.shared.post(
                "/api/messages/read-all"
            )
            unreadCount = response.unreadCount
        } catch {
            // 忽略，下拉刷新会重新同步
        }
    }
}

struct MessagesView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    @StateObject private var viewModel = MessagesViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if viewModel.isLoading {
                    LoadingRowsView(count: 4)
                } else if let error = viewModel.error, viewModel.items.isEmpty {
                    ErrorStateView(message: error) {
                        Task { await viewModel.reload() }
                    }
                } else if viewModel.items.isEmpty {
                    EmptyStateView(
                        icon: "bell.slash",
                        title: "暂无站内消息",
                        message: "评论回复、问题反馈处理结果等通知会显示在这里。"
                    )
                } else {
                    ForEach(viewModel.items) { message in
                        MessageCard(
                            message: message,
                            isUnread: viewModel.isUnread(message),
                            onOpenLink: linkAction(for: message)
                        )
                        .onTapGesture {
                            Task {
                                await viewModel.markRead(message)
                                await session.refreshProfile()
                            }
                        }
                        .onAppear {
                            if message.id == viewModel.items.last?.id {
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
        .navigationTitle("站内消息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("全部已读") {
                    Task {
                        await viewModel.markAllRead()
                        await session.refreshProfile()
                    }
                }
                .font(.caption)
                .disabled(viewModel.unreadCount == 0)
            }
        }
        .refreshable {
            await viewModel.reload()
            await session.refreshProfile()
        }
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    private func linkAction(for message: Message) -> (() -> Void)? {
        guard let value = message.url, !value.isEmpty else { return nil }

        return {
            if let url = AppConfig.shared.absoluteURL(from: value) {
                openURL(url)
            }
        }
    }
}

struct MessageCard: View {
    let message: Message
    let isUnread: Bool
    var onOpenLink: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(isUnread ? Theme.blue : Color.clear)
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.title)
                        .font(.subheadline.weight(isUnread ? .bold : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 6)

                    if let onOpenLink {
                        Button(action: onOpenLink) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let body = message.body, !body.isEmpty {
                    Text(body.htmlToPlainText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }

                Text(DateText.relative(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isUnread ? Theme.cardBackground : Theme.cardBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(isUnread ? Theme.blue.opacity(0.18) : Color.primary.opacity(0.04), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
