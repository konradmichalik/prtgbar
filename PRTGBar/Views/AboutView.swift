import SwiftUI

struct AboutView: View {
    @State private var updateState: UpdateCheckState = .idle

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 48)

            Text("PRTGBar")
                .font(.headline)

            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/konradmichalik/prtgbar")!)
            } label: {
                Label("GitHub Repository", systemImage: "link")
            }
            .buttonStyle(.bordered)

            updateCheckSection

            Text("\u{00A9} 2026 Konrad Michalik")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    @ViewBuilder
    private var updateCheckSection: some View {
        switch updateState {
        case .idle:
            Button("Check for Updates") {
                Task { await checkForUpdates() }
            }
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            Label("You're up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .available(let version, let url):
            VStack(spacing: 6) {
                Label("Version \(version) available", systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                Link("Download", destination: url)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func checkForUpdates() async {
        updateState = .checking

        guard let url = URL(string: "https://api.github.com/repos/konradmichalik/prtgbar/releases/latest") else {
            updateState = .error("Invalid URL")
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

            if latestVersion == appVersion {
                updateState = .upToDate
            } else if let releaseURL = URL(string: release.htmlUrl) {
                updateState = .available(version: latestVersion, url: releaseURL)
            } else {
                updateState = .error("Could not parse release URL")
            }
        } catch {
            updateState = .error("Could not check for updates")
        }
    }
}

private enum UpdateCheckState {
    case idle
    case checking
    case upToDate
    case available(version: String, url: URL)
    case error(String)
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}
