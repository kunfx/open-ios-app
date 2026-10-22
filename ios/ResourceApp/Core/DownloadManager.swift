import Combine
import Foundation

// MARK: - 下载任务模型

struct DownloadItem: Codable, Identifiable, Equatable {
    enum State: String, Codable {
        case queued
        case downloading
        case paused
        case completed
        case failed
    }

    let id: UUID
    let appID: Int
    let appName: String
    let appIcon: String?
    let linkTitle: String
    let remoteURL: String
    var fileName: String
    var totalBytes: Int64
    var downloadedBytes: Int64
    var state: State
    var errorMessage: String?
    let createdAt: Date
    var completedAt: Date?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(downloadedBytes) / Double(totalBytes)))
    }

    var isActive: Bool {
        state == .queued || state == .downloading
    }

    var sizeText: String {
        if totalBytes > 0 {
            return Self.bytes(totalBytes)
        }

        if downloadedBytes > 0 {
            return Self.bytes(downloadedBytes)
        }

        return "未知大小"
    }

    var progressText: String {
        switch state {
        case .queued:
            return "等待下载"
        case .downloading:
            if totalBytes > 0 {
                return "\(Self.bytes(downloadedBytes)) / \(Self.bytes(totalBytes)) · \(Int(progress * 100))%"
            }
            return Self.bytes(downloadedBytes)
        case .paused:
            return totalBytes > 0 ? "已暂停 · \(Int(progress * 100))%" : "已暂停"
        case .completed:
            return "下载完成 · \(sizeText)"
        case .failed:
            return errorMessage ?? "下载失败"
        }
    }

    /// 本地文件地址（只有下载完成后才存在）。
    var fileURL: URL? {
        DownloadStore.fileURL(for: fileName)
    }

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(0, value))
    }
}

// MARK: - 本地存储

enum DownloadStore {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        let url = base.appendingPathComponent("ResourceDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var indexURL: URL {
        directory.appendingPathComponent("downloads.json")
    }

    static func fileURL(for name: String) -> URL? {
        guard !name.isEmpty else { return nil }

        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func resumeURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString + ".resume")
    }
}

// MARK: - 下载管理器

/// App 内置下载管理器：负责排队、进度、暂停/继续、失败重试、本地文件保存。
/// 所有公开方法都在主线程调用；URLSession 回调会切回主线程更新界面。
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    enum EnqueueResult {
        case started
        case duplicate
        case invalidURL
    }

    @Published private(set) var items: [DownloadItem] = []

    private var session: URLSession!
    private var taskMap: [UUID: URLSessionDownloadTask] = [:]
    private var pausedIDs: Set<UUID> = []
    private var lastPersistAt = Date.distantPast

    private override init() {
        super.init()

        load()

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 3
        configuration.waitsForConnectivity = true
        configuration.allowsCellularAccess = true
        configuration.httpMaximumConnectionsPerHost = 3

        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        markInterruptedTasks()
    }

    var activeCount: Int {
        items.filter(\.isActive).count
    }

    // MARK: 入队与任务控制

    @discardableResult
    func enqueue(app: AppItem, link: DownloadLink) -> EnqueueResult {
        let raw = link.path ?? link.url

        guard let url = AppConfig.shared.absoluteURL(from: raw) else {
            return .invalidURL
        }

        if let existing = items.first(where: { $0.appID == app.id && $0.linkTitle == link.title }) {
            switch existing.state {
            case .queued, .downloading:
                return .duplicate
            case .paused:
                resume(existing)
                return .started
            case .completed, .failed:
                remove(existing)
            }
        }

        let item = DownloadItem(
            id: UUID(),
            appID: app.id,
            appName: app.name,
            appIcon: app.icon,
            linkTitle: link.title,
            remoteURL: url.absoluteString,
            fileName: Self.makeFileName(app: app, title: link.title),
            totalBytes: 0,
            downloadedBytes: 0,
            state: .queued,
            errorMessage: nil,
            createdAt: Date(),
            completedAt: nil
        )

        items.insert(item, at: 0)
        persist()
        start(item.id)

        return .started
    }

    func pause(_ item: DownloadItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        pausedIDs.insert(item.id)

        if let task = taskMap[item.id] {
            task.cancel(byProducingResumeData: { resumeData in
                guard let resumeData, !resumeData.isEmpty else { return }
                try? resumeData.write(to: DownloadStore.resumeURL(for: item.id), options: .atomic)
            })
        }

        items[index].state = .paused
        items[index].errorMessage = nil
        persist()
    }

    func resume(_ item: DownloadItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        pausedIDs.remove(item.id)

        let resumeFile = DownloadStore.resumeURL(for: item.id)

        if let data = try? Data(contentsOf: resumeFile), !data.isEmpty {
            let task = session.downloadTask(withResumeData: data)
            task.taskDescription = item.id.uuidString
            taskMap[item.id] = task

            items[index].state = .downloading
            items[index].errorMessage = nil
            persist()

            try? FileManager.default.removeItem(at: resumeFile)
            task.resume()
            return
        }

        items[index].downloadedBytes = 0
        items[index].totalBytes = 0
        items[index].state = .queued
        items[index].errorMessage = nil
        persist()

        start(item.id)
    }

    func retry(_ item: DownloadItem) {
        try? FileManager.default.removeItem(at: DownloadStore.resumeURL(for: item.id))

        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        items[index].downloadedBytes = 0
        items[index].totalBytes = 0
        items[index].state = .queued
        items[index].errorMessage = nil
        pausedIDs.remove(item.id)
        persist()

        start(item.id)
    }

    func remove(_ item: DownloadItem) {
        taskMap[item.id]?.cancel()
        taskMap[item.id] = nil
        pausedIDs.remove(item.id)

        if let url = item.fileURL {
            try? FileManager.default.removeItem(at: url)
        }

        try? FileManager.default.removeItem(at: DownloadStore.resumeURL(for: item.id))

        items.removeAll { $0.id == item.id }
        persist()
    }

    func pauseAll() {
        items.filter(\.isActive).forEach { pause($0) }
    }

    func resumeAll() {
        items.filter { $0.state == .paused || $0.state == .failed }.forEach { resume($0) }
    }

    func clearCompleted() {
        items.filter { $0.state == .completed }.forEach { remove($0) }
    }

    // MARK: 内部任务

    private func start(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let url = URL(string: items[index].remoteURL) else {
            return
        }

        pausedIDs.remove(id)

        let task = session.downloadTask(with: url)
        task.taskDescription = id.uuidString
        taskMap[id] = task

        items[index].state = .downloading
        items[index].errorMessage = nil
        items[index].completedAt = nil
        persist()

        task.resume()
    }

    private func finish(id: UUID, temp: URL, suggestedName: String?) {
        taskMap[id] = nil

        guard let index = items.firstIndex(where: { $0.id == id }) else {
            try? FileManager.default.removeItem(at: temp)
            return
        }

        var name = items[index].fileName

        if let suggestedName, !suggestedName.isEmpty {
            let ext = (suggestedName as NSString).pathExtension

            if !ext.isEmpty, ext.count <= 8 {
                name = (name as NSString).deletingPathExtension + "." + ext.lowercased()
            }
        }

        let destination = DownloadStore.directory.appendingPathComponent(name)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)

        do {
            try fileManager.moveItem(at: temp, to: destination)

            let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? items[index].totalBytes

            items[index].fileName = name
            items[index].downloadedBytes = size
            items[index].totalBytes = size
            items[index].state = .completed
            items[index].completedAt = Date()
            items[index].errorMessage = nil
        } catch {
            items[index].state = .failed
            items[index].errorMessage = "无法保存文件：\(error.localizedDescription)"
        }

        persist()
    }

    private func fail(id: UUID, message: String) {
        taskMap[id] = nil

        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        items[index].state = .failed
        items[index].errorMessage = message
        persist()
    }

    // MARK: 持久化

    private func load() {
        guard let data = try? Data(contentsOf: DownloadStore.indexURL),
              let stored = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            return
        }

        items = stored
    }

    private func markInterruptedTasks() {
        var changed = false

        for index in items.indices {
            switch items[index].state {
            case .queued, .downloading:
                items[index].state = .failed
                items[index].errorMessage = "下载已中断，请点击重试"
                changed = true

            case .completed:
                if items[index].fileURL == nil {
                    items[index].state = .failed
                    items[index].errorMessage = "本地文件已被清理，请重新下载"
                    changed = true
                }

            case .paused, .failed:
                break
            }
        }

        if changed {
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: DownloadStore.indexURL, options: .atomic)
    }

    private func persistThrottled() {
        let now = Date()

        guard now.timeIntervalSince(lastPersistAt) >= 2 else { return }

        lastPersistAt = now
        persist()
    }

    private static func makeFileName(app: AppItem, title: String) -> String {
        let raw = "\(app.name)-\(title)"
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|\n\r")

        var safe = raw
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")

        if safe.count > 80 {
            safe = String(safe.prefix(80))
        }

        if safe.isEmpty {
            safe = "resource-\(app.id)"
        }

        return "\(app.id)-\(safe).ipa"
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let raw = downloadTask.taskDescription, let id = UUID(uuidString: raw) else { return }

        DispatchQueue.main.async {
            guard let index = self.items.firstIndex(where: { $0.id == id }) else { return }

            self.items[index].downloadedBytes = totalBytesWritten

            if totalBytesExpectedToWrite > 0 {
                self.items[index].totalBytes = totalBytesExpectedToWrite
            }

            self.persistThrottled()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let raw = downloadTask.taskDescription, let id = UUID(uuidString: raw) else { return }

        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            DispatchQueue.main.async {
                self.fail(id: id, message: "下载失败（HTTP \(http.statusCode)），请回详情页重新获取链接")
            }
            return
        }

        let temp = DownloadStore.directory.appendingPathComponent(id.uuidString + ".part")
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: temp)

        do {
            try fileManager.moveItem(at: location, to: temp)
        } catch {
            DispatchQueue.main.async {
                self.fail(id: id, message: "保存下载文件失败：\(error.localizedDescription)")
            }
            return
        }

        let suggestedName = downloadTask.response?.suggestedFilename

        DispatchQueue.main.async {
            self.finish(id: id, temp: temp, suggestedName: suggestedName)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard error != nil,
              let raw = task.taskDescription,
              let id = UUID(uuidString: raw) else {
            return
        }

        DispatchQueue.main.async {
            guard self.items.contains(where: { $0.id == id }) else { return }
            guard !self.pausedIDs.contains(id) else { return }

            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }

            self.fail(id: id, message: error?.localizedDescription ?? "下载失败")
        }
    }
}
