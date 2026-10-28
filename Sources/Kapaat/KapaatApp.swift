import SwiftUI
import AppKit

@main
struct KapaatApp: App {
    @StateObject private var server = ServerManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(server)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// Use the bundled Kapaat icon; fall back to SF Symbol if it isn't in the bundle.
    @ViewBuilder
    private var menuBarLabel: some View {
        if let nsImage = NSImage(named: "AppIcon") {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "archivebox.fill")
        }
    }
}
