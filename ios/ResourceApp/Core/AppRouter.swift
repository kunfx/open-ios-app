import Combine
import Foundation

enum AppTab: Hashable {
    case apps
    case games
    case trolls
    case downloads
    case profile
}

/// 全局导航状态：详情页开始下载后可以直接切到「下载」标签。
@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .apps
}
