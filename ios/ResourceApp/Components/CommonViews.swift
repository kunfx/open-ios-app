import SwiftUI

struct RemoteImage: View {
    let urlString: String?
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let url = AppConfig.shared.absoluteURL(from: urlString) {
                AsyncImage(
                    url: url,
                    transaction: Transaction(animation: .easeInOut(duration: 0.2))
                ) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            placeholder
                            ProgressView()
                                .controlSize(.small)
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.accent.opacity(0.20), Theme.blue.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct AppIconView: View {
    let urlString: String?
    var size: CGFloat = 56

    var body: some View {
        RemoteImage(urlString: urlString)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

struct AvatarView: View {
    let urlString: String?
    let name: String
    var size: CGFloat = 64

    var body: some View {
        Group {
            if urlString?.isEmpty == false {
                RemoteImage(urlString: urlString)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Theme.accent, Theme.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 2))
    }
}

struct Tag: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.13))
            .clipShape(Capsule())
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

struct AppRow: View {
    let app: AppItem

    var body: some View {
        HStack(spacing: 12) {
            AppIconView(urlString: app.icon, size: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(app.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let description = app.shortDescription, !description.isEmpty {
                    Text(description.htmlToPlainText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 5) {
                if app.isFree {
                    Tag(text: "免费")
                } else {
                    Tag(text: "\(app.pointsRequired) 积分", color: Theme.gold)
                }

                if app.unlocked {
                    Text("已解锁")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("v\(app.version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.045), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct EmptyStateView: View {
    var icon: String = "tray"
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if let retry {
                Button("重试", action: retry)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.13))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

struct LoadingRowsView: View {
    var count: Int = 6

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 140, height: 12)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: 90, height: 10)
                    }

                    Spacer()
                }
                .padding(12)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.accent)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
