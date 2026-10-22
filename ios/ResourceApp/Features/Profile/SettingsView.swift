import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = AppConfig.shared.baseURLString
    @State private var isTesting = false
    @State private var alertMessage: String?
    @State private var showLogoutConfirm = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                TextField("https://your-domain.com", text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.callout)

                Button {
                    saveServer()
                } label: {
                    Label("保存服务器地址", systemImage: "checkmark.circle")
                }

                Button {
                    testConnection()
                } label: {
                    HStack {
                        Label("测试连接", systemImage: "network")

                        Spacer()

                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isTesting)
            } header: {
                Text("服务器")
            } footer: {
                Text("App 不直接连接 MySQL，所有数据都通过 Laravel API 读取。修改地址后会退出当前账号。")
            }

            Section("关于") {
                LabeledContent("App 版本", value: appVersion)
                LabeledContent("当前接口", value: AppConfig.shared.baseURLString)
                    .font(.caption)

                Text("数据来自现有 Laravel 资源站。积分扣除、VIP 权限、下载地址均由服务端校验，App 界面不作为权限依据。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("恢复默认服务器") {
                    applyServer(AppConfig.defaultBaseURLString, message: "已恢复默认服务器，请重新登录")
                }

                if session.isLoggedIn {
                    Button("退出登录", role: .destructive) {
                        showLogoutConfirm = true
                    }
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("退出登录", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task {
                    await session.logout()
                }
            }

            Button("取消", role: .cancel) {}
        }
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .onAppear {
            serverURL = AppConfig.shared.baseURLString
        }
    }

    private func saveServer() {
        let normalized = AppConfig.normalize(serverURL)

        if normalized == AppConfig.shared.baseURLString {
            alertMessage = "服务器地址没有变化"
            return
        }

        applyServer(normalized, message: "服务器地址已更新，请重新登录")
    }

    private func applyServer(_ value: String, message: String) {
        AppConfig.shared.baseURLString = value
        serverURL = value

        if session.isLoggedIn {
            session.logoutLocally()
        }

        alertMessage = message
    }

    private func testConnection() {
        guard !isTesting else { return }

        let normalized = AppConfig.normalize(serverURL)
        let original = AppConfig.shared.baseURLString

        AppConfig.shared.baseURLString = normalized
        isTesting = true

        Task { @MainActor in
            defer {
                isTesting = false
                AppConfig.shared.baseURLString = original
            }

            do {
                let health: HealthResponse = try await APIClient.shared.get("/api/health")
                alertMessage = "连接成功：\(health.name ?? normalized)\n状态：\(health.status)"
            } catch {
                alertMessage = session.message(for: error)
            }
        }
    }
}
