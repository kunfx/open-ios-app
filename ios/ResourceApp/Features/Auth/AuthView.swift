import SwiftUI
import UIKit

struct AuthView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "注册"

        var id: String { rawValue }
    }

    private enum Field: Hashable {
        case email
        case password
        case confirmation
        case name
    }

    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    /// true 时作为「我的」标签页里的登录框直接嵌入，不包 NavigationStack。
    var embedded: Bool = false

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var name = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var showServerField = false
    @State private var serverURL = AppConfig.shared.baseURLString

    @FocusState private var focusedField: Field?

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle(mode.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .interactiveDismissDisabled(isSubmitting)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 22) {
                brandHeader
                modePicker
                form
                submitButton
                serverSection
                agreementText
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.groupedBackground)
    }

    private var brandHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.heroGradient)
                    .frame(width: 76, height: 76)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 14, y: 7)

                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("资源库")
                .font(.title2.weight(.black))

            Text("登录后可下载资源、查看积分与会员权益")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var modePicker: some View {
        Picker("模式", selection: $mode) {
            ForEach(Mode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _ in
            errorMessage = nil
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            if mode == .register {
                authField(
                    title: "昵称（可选）",
                    systemImage: "person",
                    text: $name,
                    field: .name,
                    contentType: .name
                )
            }

            authField(
                title: "邮箱",
                systemImage: "envelope",
                text: $email,
                field: .email,
                contentType: .username,
                keyboard: .emailAddress
            )

            VStack(alignment: .leading, spacing: 7) {
                Label("密码", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("至少 6 位", text: $password)
                                .focused($focusedField, equals: .password)
                        } else {
                            SecureField("至少 6 位", text: $password)
                                .focused($focusedField, equals: .password)
                        }
                    }
                    .textContentType(mode == .login ? .password : .newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(mode == .login ? .go : .next)
                    .onSubmit { submit() }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(13)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            if mode == .register {
                VStack(alignment: .leading, spacing: 7) {
                    Label("确认密码", systemImage: "lock.rotation")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("再次输入密码", text: $confirmation)
                        .focused($focusedField, equals: .confirmation)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(13)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }

                Text("支持 QQ、163、Gmail、新浪邮箱；同一网络仅可注册一个账号。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(errorMessage)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func authField(
        title: String,
        systemImage: String,
        text: Binding<String>,
        field: Field,
        contentType: UITextContentType,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(title, text: text)
                .focused($focusedField, equals: field)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(13)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                }

                Text(isSubmitting ? "请稍候..." : (mode == .login ? "登录" : "注册并登录"))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isSubmitting)
        .opacity(isSubmitting ? 0.7 : 1)
    }

    private var serverSection: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showServerField.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                    Text(AppConfig.shared.baseURLString)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: showServerField ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            if showServerField {
                VStack(spacing: 10) {
                    TextField("https://your-domain.com", text: $serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(12)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    Button {
                        saveServer()
                    } label: {
                        Text("保存服务器地址")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(12)
                .background(Theme.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var agreementText: some View {
        Text("登录即表示你同意合理使用站内资源，所有积分扣除与会员权限均由服务器校验。")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
    }

    private func submit() {
        guard !isSubmitting else { return }

        let emailValue = email.trimmed

        guard emailValue.contains("@"), emailValue.contains(".") else {
            errorMessage = "请输入正确的邮箱地址"
            return
        }

        guard password.count >= 6 else {
            errorMessage = "密码至少需要 6 位"
            return
        }

        if mode == .register, password != confirmation {
            errorMessage = "两次输入的密码不一致"
            return
        }

        focusedField = nil
        isSubmitting = true
        errorMessage = nil

        Task { @MainActor in
            defer { isSubmitting = false }

            do {
                if mode == .login {
                    try await session.login(email: emailValue, password: password)
                } else {
                    try await session.register(
                        email: emailValue,
                        password: password,
                        confirmation: confirmation,
                        name: name
                    )
                }

                if !embedded {
                    dismiss()
                }
            } catch {
                errorMessage = session.message(for: error)
            }
        }
    }

    private func saveServer() {
        let normalized = AppConfig.normalize(serverURL)
        serverURL = normalized
        AppConfig.shared.baseURLString = normalized

        if session.isLoggedIn {
            session.logoutLocally()
        }

        errorMessage = "服务器地址已更新，请使用新服务器的账号登录"
        showServerField = false
    }
}
