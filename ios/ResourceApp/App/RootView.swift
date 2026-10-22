import Combine
import SwiftUI

struct RootView: View {
    @StateObject private var session = SessionStore()
    @StateObject private var router = AppRouter()

    @State private var activeDownloads = 0

    private let downloads = DownloadManager.shared

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack {
                CategoryRootView(
                    title: "应用",
                    categoryName: "应用",
                    fallbackSlug: "apps"
                )
            }
            .tabItem {
                Label("应用", systemImage: "square.grid.2x2.fill")
            }
            .tag(AppTab.apps)

            NavigationStack {
                CategoryRootView(
                    title: "游戏",
                    categoryName: "游戏",
                    fallbackSlug: "games"
                )
            }
            .tabItem {
                Label("游戏", systemImage: "gamecontroller.fill")
            }
            .tag(AppTab.games)

            NavigationStack {
                CategoryRootView(
                    title: "巨魔",
                    categoryName: "巨魔",
                    fallbackSlug: "trolls"
                )
            }
            .tabItem {
                Label("巨魔", systemImage: "wrench.and.screwdriver.fill")
            }
            .tag(AppTab.trolls)

            NavigationStack {
                DownloadsView()
            }
            .tabItem {
                Label("下载", systemImage: "arrow.down.circle.fill")
            }
            .badge(activeDownloads)
            .tag(AppTab.downloads)

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("我的", systemImage: "person.crop.circle.fill")
            }
            .tag(AppTab.profile)
        }
        .tint(Theme.accent)
        .environmentObject(session)
        .environmentObject(router)
        .onReceive(
            downloads.$items
                .map { items in items.filter { $0.isActive }.count }
                .removeDuplicates()
        ) { count in
            activeDownloads = count
        }
        .task {
            await session.restore()
        }
    }
}
