import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var showLogoutConfirm = false
    @State private var isSigningIn = false
    @State private var alertMessage: String?

    var body: some View {
        Group {
            if session.isLoggedIn, let user = session.user {
                loggedInContent(user)
            } else if session.isLoggedIn {
                VStack(spacing: 14) {
                    ProgressView()

                    Text("正在同步账号资料")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("重新同步") {
                        Task { await session.refreshProfile() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.groupedBackground)
            } else {
                AuthView(embedded: true)
            }
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task {
            if session.isLoggedIn {
                await session.refreshProfile()
            }
        }
        .confirmationDialog("退出登录", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await session.logout() }
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("退出后需要重新输入账号密码。")
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

    private func loggedInContent(_ user: User) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if user.mustChangePassword {
                    passwordBanner
                }

                userHeader(user)
                vipCard(user)
                statRow(user)
                signInButton(user)
                siteMenu
                moreMenu
                logoutButton

                Text("积分扣除、会员权限与下载额度均由服务器实时校验。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .background(Theme.groupedBackground)
        .refreshable {
            await session.refreshProfile()
        }
    }

    // MARK: 账号头部

    private var passwordBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(Theme.gold)

            VStack(alignment: .leading, spacing: 3) {
                Text("账号仍在使用初始密码")
                    .font(.footnote.weight(.semibold))
                Text("为了账号安全，请尽快在「修改资料」中修改密码。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(Theme.gold.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func userHeader(_ user: User) -> some View {
        HStack(spacing: 14) {
            AvatarView(urlString: user.avatar, name: user.name, size: 66)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(user.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)

                    if user.isAdmin || user.vipActive {
                        Tag(text: user.badgeText, color: user.isAdmin ? Theme.pink : Theme.purple)
                    }
                }

                Text(user.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(user.vipActive ? "会员到期：\(user.vipExpiredText)" : "注册于 \(DateText.day(user.createdAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func vipCard(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(Theme.gold)

                Text(user.vipActive ? "会员权益生效中" : "开通会员")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                Spacer()

                Text(user.vipActive ? user.vipExpiredText : "会员免费")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Text(user.vipActive
                 ? "全站付费资源免费下载，不受每日免费额度限制。"
                 : "有效会员可免费下载全站付费资源。可前往「升级会员」了解开通方式。")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Theme.vipGradient)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func statRow(_ user: User) -> some View {
        HStack(spacing: 10) {
            statCard(title: "积分", value: "\(user.points)", tint: Theme.gold)
            statCard(title: "今日免费剩余", value: user.freeLeftText, tint: Theme.accent)
            statCard(title: "签到", value: user.signedToday ? "已签" : "未签", tint: Theme.blue)
        }
    }

    private func statCard(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func signInButton(_ user: User) -> some View {
        Button {
            signIn()
        } label: {
            HStack(spacing: 7) {
                if isSigningIn {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: user.signedToday ? "checkmark.circle.fill" : "calendar.badge.plus")
                }

                Text(user.signedToday ? "今日已签到" : "每日签到")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(user.signedToday || isSigningIn)
        .opacity(user.signedToday ? 0.55 : 1)
    }

    // MARK: 与 PHP 网站一致的子菜单

    private var siteMenu: some View {
        VStack(spacing: 0) {
            siteMenuPrimary
            siteMenuSecondary
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var siteMenuPrimary: some View {
        VStack(spacing: 0) {
            NavigationLink {
                EditProfileView()
            } label: {
                ProfileRow(icon: "pencil", title: "修改资料", tint: Theme.blue)
            }
            .buttonStyle(.plain)

            rowDivider

            NavigationLink {
                DownloadHistoryView()
            } label: {
                ProfileRow(icon: "arrow.down.circle.fill", title: "下载记录", tint: Theme.accent)
            }
            .buttonStyle(.plain)

            rowDivider

            webRow(
                title: "签名证书",
                subtitle: "网页版",
                icon: "checkmark.seal.fill",
                tint: Theme.purple,
                path: "/user/cer-shop"
            )

            rowDivider

            webRow(
                title: "升级会员",
                subtitle: "网页版",
                icon: "crown.fill",
                tint: Theme.gold,
                path: "/user/upgrade-vip"
            )

            rowDivider

            NavigationLink {
                PointsView()
            } label: {
                ProfileRow(icon: "list.bullet.rectangle.portrait.fill", title: "我的积分", tint: Theme.blue)
            }
            .buttonStyle(.plain)
        }
    }

    private var siteMenuSecondary: some View {
        VStack(spacing: 0) {
            rowDivider

            NavigationLink {
                EarnPointsView()
            } label: {
                ProfileRow(icon: "gift.fill", title: "赚取积分", tint: Theme.pink)
            }
            .buttonStyle(.plain)

            rowDivider

            webRow(
                title: "我的订单",
                subtitle: "网页版",
                icon: "bag.fill",
                tint: Theme.accentDeep,
                path: "/user/my-orders"
            )

            rowDivider

            webRow(
                title: "问题反馈",
                subtitle: "网页版",
                icon: "questionmark.bubble.fill",
                tint: Theme.gold,
                path: "/user/my-tickets"
            )
        }
    }

    private var moreMenu: some View {
        VStack(spacing: 0) {
            NavigationLink {
                MessagesView()
            } label: {
                ProfileRow(
                    icon: "bell.fill",
                    title: "站内消息",
                    badge: session.user?.unreadMessages ?? 0,
                    tint: Theme.pink
                )
            }
            .buttonStyle(.plain)

            rowDivider

            NavigationLink {
                ArticlesView()
            } label: {
                ProfileRow(icon: "book.fill", title: "教程文章", tint: Theme.purple)
            }
            .buttonStyle(.plain)

            rowDivider

            NavigationLink {
                SettingsView()
            } label: {
                ProfileRow(icon: "server.rack", title: "服务器设置", tint: .secondary)
            }
            .buttonStyle(.plain)
        }
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 46)
    }

    @ViewBuilder
    private func webRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        path: String
    ) -> some View {
        if let url = AppConfig.shared.absoluteURL(from: path) {
            Link(destination: url) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                        .frame(width: 26)

                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var logoutButton: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            Text("退出登录")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 签到

    private func signIn() {
        guard !isSigningIn else { return }

        isSigningIn = true

        Task { @MainActor in
            defer { isSigningIn = false }

            do {
                let result: SignInResult = try await APIClient.shared.post("/api/user/sign-in")
                session.apply(result.user)
                alertMessage = "签到成功，获得 \(result.pointsGained) 积分，已连续签到 \(result.continuousDays) 天"
            } catch {
                alertMessage = session.message(for: error)
            }
        }
    }
}

struct ProfileRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var badge: Int = 0
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 26)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
            } else if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
