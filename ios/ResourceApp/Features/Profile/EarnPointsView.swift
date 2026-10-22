import SwiftUI
import UIKit

struct InvitationStats: Decodable {
    let inviteLink: String
    let count: Int
    let points: Int

    enum CodingKeys: String, CodingKey {
        case inviteLink = "invite_link"
        case count
        case points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        inviteLink = try container.decodeIfPresent(String.self, forKey: .inviteLink) ?? ""
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        points = try container.decodeIfPresent(Int.self, forKey: .points) ?? 0
    }
}

/// 「我的 → 赚取积分」，对应网站个人中心的签到与邀请奖励。
struct EarnPointsView: View {
    @EnvironmentObject private var session: SessionStore

    @State private var stats: InvitationStats?
    @State private var isLoadingStats = false
    @State private var isSigningIn = false
    @State private var alertMessage: String?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                signCard
                inviteCard
                rulesCard
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("赚取积分")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadStats()
            await session.refreshProfile()
        }
        .task {
            await loadStats()
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

    private var signCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(Theme.accent)

                Text("每日签到")
                    .font(.headline)

                Spacer()

                Text("\(session.user?.points ?? 0) 积分")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.gold)
            }

            Text(session.user?.signedToday == true
                 ? "今天已经签到，明天记得再来。连续签到还能获得额外奖励。"
                 : "每天签到可领取积分，连续签到达到指定天数还有额外奖励。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                signIn()
            } label: {
                HStack(spacing: 7) {
                    if isSigningIn {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: session.user?.signedToday == true ? "checkmark.circle.fill" : "hand.tap.fill")
                    }

                    Text(session.user?.signedToday == true ? "今日已签到" : "立即签到")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSigningIn || session.user?.signedToday == true)
            .opacity(session.user?.signedToday == true ? 0.55 : 1)
        }
        .cardStyle()
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.badge.plus.fill")
                    .foregroundStyle(Theme.pink)

                Text("邀请好友")
                    .font(.headline)

                Spacer()
            }

            Text("把邀请链接发给朋友，好友注册后你可以获得积分奖励。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isLoadingStats {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载邀请数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let stats, !stats.inviteLink.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(stats.inviteLink)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = stats.inviteLink
                            copied = true

                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                copied = false
                            }
                        } label: {
                            Label(copied ? "已复制" : "复制链接", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("已邀请 \(stats.count) 人 · 获得 \(stats.points) 积分")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Theme.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("暂时无法获取邀请链接，请稍后下拉刷新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("积分说明")
                .font(.headline)

            ruleLine("每日签到可获得基础积分，连续签到有额外奖励。")
            ruleLine("邀请好友注册成功后，邀请奖励由服务器自动发放。")
            ruleLine("积分可用于下载付费资源；有效会员下载付费资源不扣积分。")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func ruleLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

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

    private func loadStats() async {
        guard session.isLoggedIn else { return }

        isLoadingStats = true
        defer { isLoadingStats = false }

        do {
            stats = try await APIClient.shared.get("/api/user/invitations")
        } catch {
            // 邀请统计失败不影响签到
        }
    }
}
