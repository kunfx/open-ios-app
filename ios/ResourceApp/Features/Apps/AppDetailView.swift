import SwiftUI

@MainActor
final class AppDetailViewModel: ObservableObject {
    @Published private(set) var app: AppItem?
    @Published private(set) var isLoading = false
    @Published var error: String?

    let appID: Int

    init(appID: Int, preview: AppItem?) {
        self.appID = appID
        app = preview
    }

    func load() async {
        isLoading = true
        error = nil

        do {
            app = try await APIClient.shared.get("/api/apps/\(appID)")
        } catch let apiError as APIError {
            if !apiError.isCancelled, app == nil {
                error = apiError.localizedDescription
            }
        } catch {
            if app == nil {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }

    func markUnlocked() {
        guard var current = app else { return }
        current.unlocked = true
        app = current
    }
}

private enum DetailAlert: Identifiable {
    case confirm(points: Int, balance: Int)
    case message(String)

    var id: String {
        switch self {
        case .confirm(let points, let balance):
            return "confirm-\(points)-\(balance)"
        case .message(let message):
            return "message-\(message)"
        }
    }
}

struct ScreenshotPreview: Identifiable {
    let id = UUID()
    let images: [String]
    let index: Int
}

struct DownloadSheetPayload: Identifiable {
    let id = UUID()
    let app: AppItem
    let result: DownloadResult
}

struct AppDetailView: View {
    let appID: Int

    @StateObject private var viewModel: AppDetailViewModel
    @EnvironmentObject private var session: SessionStore

    @State private var showAuth = false
    @State private var isDownloading = false
    @State private var alert: DetailAlert?
    @State private var downloadSheet: DownloadSheetPayload?
    @State private var screenshotPreview: ScreenshotPreview?

    init(appID: Int, preview: AppItem? = nil) {
        self.appID = appID
        _viewModel = StateObject(
            wrappedValue: AppDetailViewModel(appID: appID, preview: preview)
        )
    }

    init(app: AppItem) {
        self.init(appID: app.id, preview: app)
    }

    var body: some View {
        ScrollView {
            if let app = viewModel.app {
                detailContent(app)
            } else if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载资源详情")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 100)
            } else if let error = viewModel.error {
                ErrorStateView(message: error) {
                    Task { await viewModel.load() }
                }
                .padding(.top, 60)
            }
        }
        .background(Theme.groupedBackground)
        .navigationTitle(viewModel.app?.name ?? "资源详情")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .task {
            if viewModel.app == nil {
                await viewModel.load()
            } else {
                // 有预览数据时后台静默刷新完整详情
                await viewModel.load()
            }
        }
        .sheet(isPresented: $showAuth) {
            AuthView()
        }
        .sheet(item: $downloadSheet) { payload in
            DownloadLinksSheet(app: payload.app, result: payload.result)
        }
        .sheet(item: $screenshotPreview) { preview in
            ScreenshotViewer(preview: preview)
        }
        .alert(item: $alert) { item in
            switch item {
            case .confirm(let points, let balance):
                return Alert(
                    title: Text("确认下载"),
                    message: Text("本资源需要消耗 \(points) 积分，当前余额 \(balance) 积分。\n积分扣除由服务器判断并执行。"),
                    primaryButton: .default(Text("确认下载")) {
                        Task { await confirmDownload() }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .message(let message):
                return Alert(
                    title: Text("提示"),
                    message: Text(message),
                    dismissButton: .default(Text("好的"))
                )
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if let app = viewModel.app {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.isFree ? "免费资源" : "\(app.pointsRequired) 积分")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(downloadHint(app))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    startDownload(app)
                } label: {
                    HStack(spacing: 6) {
                        if isDownloading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }

                        Text(isDownloading ? "处理中" : (app.unlocked ? "再次下载" : "立即下载"))
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Theme.heroGradient)
                    .clipShape(Capsule())
                }
                .disabled(isDownloading)
                .opacity(isDownloading ? 0.7 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }

    private func detailContent(_ app: AppItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header(app)
            metaRow(app)

            infoCard(title: "应用简介") {
                Text(app.plainDescription.isEmpty ? "该作者暂时没有填写简介。" : app.plainDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !app.screenshots.isEmpty {
                screenshotsSection(app)
            }

            if !app.modLines.isEmpty {
                infoCard(title: "功能说明") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(app.modLines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                                    .padding(.top, 3)

                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !app.downloadLinks.isEmpty {
                downloadInfoCard(app)
            }

            Text("下载地址由服务器按账号权限生成，2 小时内有效。请勿分享给他人。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
        }
        .padding(16)
    }

    private func header(_ app: AppItem) -> some View {
        HStack(alignment: .top, spacing: 15) {
            AppIconView(urlString: app.icon, size: 92)

            VStack(alignment: .leading, spacing: 7) {
                Text(app.name)
                    .font(.title3.weight(.black))
                    .lineLimit(2)

                Text(app.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if app.isFree {
                        Tag(text: "免费资源")
                    } else {
                        Tag(text: "\(app.pointsRequired) 积分", color: Theme.gold)
                        Tag(text: "会员免费", color: Theme.blue)
                    }

                    if app.unlocked {
                        Tag(text: "已解锁", color: Theme.accentDeep)
                    }
                }

                if let path = categoryPath(app) {
                    Text(path)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func metaRow(_ app: AppItem) -> some View {
        HStack(spacing: 0) {
            metaItem(title: "版本", value: "v\(app.version)")
            Divider().frame(height: 30)
            metaItem(title: "大小", value: app.size)
            Divider().frame(height: 30)
            metaItem(title: "浏览", value: "\(app.views)")
        }
        .padding(.vertical, 13)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metaItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func infoCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func screenshotsSection(_ app: AppItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "应用截图")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(app.screenshots.enumerated()), id: \.offset) { index, image in
                        Button {
                            screenshotPreview = ScreenshotPreview(images: app.screenshots, index: index)
                        } label: {
                            RemoteImage(urlString: image)
                                .frame(width: 170, height: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func downloadInfoCard(_ app: AppItem) -> some View {
        infoCard(title: "下载版本") {
            VStack(spacing: 9) {
                ForEach(app.downloadLinks) { link in
                    HStack(spacing: 10) {
                        Image(systemName: "link.circle.fill")
                            .foregroundStyle(Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.title)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.primary)

                            let detail = [link.linkType, link.remark]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: " · ")

                            if !detail.isEmpty {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Theme.elevatedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func categoryPath(_ app: AppItem) -> String? {
        var parts: [String] = []

        if let main = app.mainCategory?.name {
            parts.append(main)
        }

        if let category = app.category?.name, category != parts.first {
            parts.append(category)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    private func downloadHint(_ app: AppItem) -> String {
        if let user = session.user {
            if user.unlimitedDownloads {
                return app.isFree ? "会员不限次数" : "会员免费下载"
            }

            return app.isFree ? "今日剩余 \(user.freeLeftText) 次" : "会员免费下载"
        }

        return "登录后下载"
    }

    private func startDownload(_ app: AppItem) {
        guard session.isLoggedIn else {
            showAuth = true
            return
        }

        guard !isDownloading else { return }

        isDownloading = true

        Task { @MainActor in
            defer { isDownloading = false }

            do {
                let result: DownloadResult = try await APIClient.shared.post(
                    "/api/apps/\(appID)/download"
                )
                handle(result)
            } catch {
                alert = .message(session.message(for: error))
            }
        }
    }

    private func confirmDownload() async {
        guard session.isLoggedIn else {
            showAuth = true
            return
        }

        guard !isDownloading else { return }

        isDownloading = true
        defer { isDownloading = false }

        do {
            let result: DownloadResult = try await APIClient.shared.post(
                "/api/apps/\(appID)/download/confirm"
            )
            handle(result)
        } catch {
            alert = .message(session.message(for: error))
        }
    }

    private func handle(_ result: DownloadResult) {
        switch result.status {
        case "REQUIRE_CONFIRM":
            alert = .confirm(
                points: result.pointsRequired ?? 0,
                balance: result.userPoints ?? session.user?.points ?? 0
            )
        case "DOWNLOAD_READY", "REPEAT_DOWNLOAD", "FREE_LIMIT_NOTIFY":
            guard !result.downloadLinks.isEmpty else {
                alert = .message(result.message ?? "下载地址生成失败，请稍后再试")
                return
            }

            viewModel.markUnlocked()

            if let app = viewModel.app {
                downloadSheet = DownloadSheetPayload(app: app, result: result)
            }

            Task {
                await session.refreshProfile()
            }
        default:
            alert = .message(result.message ?? "暂时无法下载，请稍后再试")
        }
    }
}

struct DownloadLinksSheet: View {
    let app: AppItem
    let result: DownloadResult

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter

    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.accent)

                        Text("下载已就绪")
                            .font(.title3.weight(.bold))

                        if let message = result.message, !message.isEmpty {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        if let spent = result.pointsSpent, spent > 0 {
                            Text("本次消耗 \(spent) 积分")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    .padding(.top, 12)

                    VStack(spacing: 9) {
                        ForEach(result.downloadLinks) { link in
                            Button {
                                start(link)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(Theme.accent)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(link.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)

                                        let detail = [link.linkType, link.remark]
                                            .compactMap { $0 }
                                            .filter { !$0.isEmpty }
                                            .joined(separator: " · ")

                                        if !detail.isEmpty {
                                            Text(detail)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer(minLength: 0)

                                    Text("开始下载")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Theme.accent)
                                }
                                .padding(13)
                                .background(Theme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("文件由 App 内置下载器保存，不会打开浏览器。可到「下载」标签查看进度，完成后可分享或导出。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 18)
                }
                .padding(18)
            }
            .background(Theme.groupedBackground)
            .navigationTitle("下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("提示", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
        .onAppear {
            Task {
                await session.refreshProfile()
            }
        }
    }

    private func start(_ link: DownloadLink) {
        switch DownloadManager.shared.enqueue(app: app, link: link) {
        case .started:
            router.selectedTab = .downloads
            dismiss()

        case .duplicate:
            alertMessage = "这个资源已经在下载列表里了，可到「下载」标签查看进度。"

        case .invalidURL:
            alertMessage = "下载地址无效，请返回详情页重新获取。"
        }
    }
}

struct ScreenshotViewer: View {
    let preview: ScreenshotPreview

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(preview: ScreenshotPreview) {
        self.preview = preview
        _index = State(initialValue: preview.index)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(preview.images.enumerated()), id: \.offset) { offset, image in
                    RemoteImage(urlString: image, contentMode: .fit)
                        .padding(.horizontal, 10)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(18)
        }
        .preferredColorScheme(.dark)
    }
}
