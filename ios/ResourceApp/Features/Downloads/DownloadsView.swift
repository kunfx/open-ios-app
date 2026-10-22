import SwiftUI

/// 第 4 个标签页：App 内置下载管理，不调用浏览器。
struct DownloadsView: View {
    @ObservedObject private var manager = DownloadManager.shared

    var body: some View {
        Group {
            if manager.items.isEmpty {
                ScrollView {
                    VStack(spacing: 18) {
                        EmptyStateView(
                            icon: "arrow.down.circle",
                            title: "还没有下载任务",
                            message: "在资源详情页点击「立即下载」，任务会出现在这里，并实时显示下载进度。"
                        )
                        .padding(.top, 50)
                    }
                    .padding(16)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        summary

                        ForEach(manager.items) { item in
                            DownloadRow(item: item)
                        }

                        Text("未签名的 IPA 不能直接安装：点击「分享」→「存储到文件」，再用 TrollStore 或电脑签名工具安装。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.top, 6)
                            .padding(.bottom, 22)
                    }
                    .padding(16)
                }
            }
        }
        .background(Theme.groupedBackground)
        .navigationTitle("下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !manager.items.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            manager.pauseAll()
                        } label: {
                            Label("全部暂停", systemImage: "pause.circle")
                        }

                        Button {
                            manager.resumeAll()
                        } label: {
                            Label("全部继续", systemImage: "play.circle")
                        }

                        Divider()

                        Button(role: .destructive) {
                            manager.clearCompleted()
                        } label: {
                            Label("清除已完成", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 9) {
            Image(systemName: manager.activeCount > 0 ? "arrow.down.circle.fill" : "tray.full.fill")
                .foregroundStyle(manager.activeCount > 0 ? Theme.accent : Color.secondary)

            Text(manager.activeCount > 0
                 ? "\(manager.activeCount) 个任务进行中"
                 : "共 \(manager.items.count) 个下载任务")
                .font(.footnote.weight(.semibold))

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 单条下载

private struct DownloadRow: View {
    let item: DownloadItem

    @ObservedObject private var manager = DownloadManager.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                AppIconView(urlString: item.appIcon, size: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.appName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(item.linkTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                actionButton
                menu
            }

            progressBar

            HStack(spacing: 8) {
                Text(item.progressText)
                    .font(.caption2)
                    .foregroundStyle(item.state == .failed ? Color.red : Color.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if item.state == .completed, let url = item.fileURL {
                    ShareLink(item: url) {
                        Label("分享", systemImage: "square.and.arrow.up")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .padding(13)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        switch item.state {
        case .queued, .downloading:
            Button {
                manager.pause(item)
            } label: {
                Image(systemName: "pause.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("暂停下载")

        case .paused:
            Button {
                manager.resume(item)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("继续下载")

        case .failed:
            Button {
                manager.retry(item)
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.gold)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重新下载")

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
        }
    }

    private var progressBar: some View {
        Group {
            if item.state == .completed {
                ProgressView(value: 1)
                    .tint(Theme.accent)
            } else if item.totalBytes > 0 {
                ProgressView(value: item.progress)
                    .tint(item.state == .failed ? Color.red : Theme.accent)
            } else {
                ProgressView()
                    .tint(Theme.accent)
            }
        }
        .progressViewStyle(.linear)
    }

    private var menu: some View {
        Menu {
            switch item.state {
            case .queued, .downloading:
                Button {
                    manager.pause(item)
                } label: {
                    Label("暂停", systemImage: "pause")
                }

            case .paused:
                Button {
                    manager.resume(item)
                } label: {
                    Label("继续", systemImage: "play")
                }

            case .failed:
                Button {
                    manager.retry(item)
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }

            case .completed:
                if let url = item.fileURL {
                    ShareLink(item: url) {
                        Label("分享 / 导出", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                manager.remove(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
    }
}
