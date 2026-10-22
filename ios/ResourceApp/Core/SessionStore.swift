import Combine
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var token: String?
    @Published private(set) var isRestoring = false

    private let tokenKey = "auth.token"
    private let userCacheKey = "auth.cachedUser"
    private let defaults = UserDefaults.standard

    init() {
        if let stored = KeychainStore.read(tokenKey) {
            token = stored
            APIClient.shared.token = stored
        }

        if let data = defaults.data(forKey: userCacheKey),
           let cached = try? JSONDecoder().decode(User.self, from: data) {
            user = cached
        }
    }

    var isLoggedIn: Bool {
        token != nil
    }

    /// 启动时用本地 token 拉取一次最新资料；token 失效会自动退出。
    func restore() async {
        guard token != nil else { return }

        isRestoring = true
        defer { isRestoring = false }

        do {
            let profile: User = try await APIClient.shared.get("/api/user/profile")
            apply(profile)
        } catch let error as APIError where error.isUnauthorized {
            logoutLocally()
        } catch {
            // 网络不可用时保留缓存的用户信息，等下拉刷新时再同步。
        }
    }

    func login(email: String, password: String) async throws {
        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "device_name": "iPhone",
        ]

        let result: AuthResponse = try await APIClient.shared.post("/api/login", body: body)
        persist(result)
    }

    func register(email: String, password: String, confirmation: String, name: String?) async throws {
        var body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
            "password": password,
            "password_confirmation": confirmation,
            "device_name": "iPhone",
        ]

        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["name"] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let result: AuthResponse = try await APIClient.shared.post("/api/register", body: body)
        persist(result)
    }

    func refreshProfile() async {
        guard isLoggedIn else { return }

        do {
            let profile: User = try await APIClient.shared.get("/api/user/profile")
            apply(profile)
        } catch let error as APIError where error.isUnauthorized {
            logoutLocally()
        } catch {
            // 静默失败，界面保留旧数据
        }
    }

    func apply(_ user: User) {
        self.user = user

        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: userCacheKey)
        }
    }

    func logout() async {
        if isLoggedIn {
            try? await APIClient.shared.postVoid("/api/logout")
        }

        logoutLocally()
    }

    func logoutLocally() {
        token = nil
        user = nil
        APIClient.shared.token = nil
        KeychainStore.delete(tokenKey)
        defaults.removeObject(forKey: userCacheKey)
    }

    /// 统一的错误提示；401 时顺手清理本地登录态。
    func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            if apiError.isUnauthorized {
                logoutLocally()
            }

            return apiError.localizedDescription
        }

        return error.localizedDescription
    }

    private func persist(_ result: AuthResponse) {
        token = result.token
        APIClient.shared.token = result.token
        KeychainStore.save(result.token, for: tokenKey)
        apply(result.user)
    }
}
