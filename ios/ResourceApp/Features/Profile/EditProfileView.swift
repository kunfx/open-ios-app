import SwiftUI

/// 「我的 → 修改资料」，对应网站个人中心的「修改资料」。
struct EditProfileView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var name = ""
    @State private var avatar = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var alertMessage: String?
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("昵称", text: $name)

                TextField("头像地址（https://…，可留空）", text: $avatar)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                LabeledContent("邮箱", value: session.user?.email ?? "")
            }

            Section {
                SecureField("新密码（不修改请留空）", text: $newPassword)
                SecureField("确认新密码", text: $confirmation)
            } header: {
                Text("修改密码")
            } footer: {
                Text("密码至少 6 位。修改后当前登录状态仍然有效。")
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack(spacing: 8) {
                        Spacer()

                        if isSaving {
                            ProgressView()
                        }

                        Text(isSaving ? "保存中…" : "保存")
                            .font(.subheadline.weight(.semibold))

                        Spacer()
                    }
                }
                .disabled(isSaving || name.trimmed.isEmpty)
            }
        }
        .navigationTitle("修改资料")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            name = session.user?.name ?? ""
            avatar = session.user?.avatar ?? ""
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

    private func save() {
        let nameValue = name.trimmed

        guard !nameValue.isEmpty else {
            alertMessage = "昵称不能为空"
            return
        }

        if !newPassword.isEmpty {
            guard newPassword.count >= 6 else {
                alertMessage = "新密码至少需要 6 位"
                return
            }

            guard newPassword == confirmation else {
                alertMessage = "两次输入的新密码不一致"
                return
            }
        }

        isSaving = true

        Task { @MainActor in
            defer { isSaving = false }

            do {
                var body: [String: Any] = ["name": nameValue]

                let avatarValue = avatar.trimmed

                if !avatarValue.isEmpty {
                    body["avatar"] = avatarValue
                }

                if !newPassword.isEmpty {
                    body["password"] = newPassword
                    body["password_confirmation"] = confirmation
                }

                let user: User = try await APIClient.shared.post("/api/user/profile", body: body)
                session.apply(user)

                newPassword = ""
                confirmation = ""
                alertMessage = "资料已保存"
            } catch {
                alertMessage = session.message(for: error)
            }
        }
    }
}
