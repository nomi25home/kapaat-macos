import SwiftUI

/// Shown when clicking the Kapaat menu-bar icon.
/// Renders the full web UI inside a fixed-size panel; below it a compact status footer.
struct MenuBarContentView: View {
    @EnvironmentObject private var server: ServerManager

    var body: some View {
        VStack(spacing: 0) {
            if server.status.isRunning {
                WebView(url: server.serverURL)
                    .frame(width: 900, height: 620)
            } else {
                splashView
                    .frame(width: 900, height: 620)
            }

            Divider()
            footer
        }
        .background(.background)
    }

    // MARK: - Sub-views

    private var splashView: some View {
        VStack(spacing: 16) {
            Image(systemName: statusIcon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(statusTitle)
                .font(.headline)
                .foregroundStyle(.secondary)

            if case .failed = server.status {
                if !server.lastError.isEmpty {
                    ScrollView {
                        Text(server.lastError)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxWidth: 760, maxHeight: 200)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Button("Retry") { server.restart() }
                    .buttonStyle(.borderedProminent)
            } else if server.status == .starting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusIcon: String {
        switch server.status {
        case .running:  return "checkmark.circle"
        case .starting: return "arrow.clockwise"
        case .failed:   return "exclamationmark.triangle"
        case .stopped:  return "archivebox"
        }
    }

    private var statusTitle: String {
        switch server.status {
        case .failed(let msg): return msg.components(separatedBy: "\n").first ?? msg
        default:               return server.status.label
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(server.status.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if server.status.isRunning {
                Button {
                    NSWorkspace.shared.open(server.serverURL)
                } label: {
                    Label("Open in Browser", systemImage: "safari")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch server.status {
        case .running:  return .green
        case .starting: return .yellow
        case .stopped:  return .gray
        case .failed:   return .red
        }
    }
}
