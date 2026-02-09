// ABOUTME: Main entry point for the Helix menu bar application.
// ABOUTME: Provides a MenuBarExtra popover, management window, and keyboard commands.

import Sparkle
import SwiftUI
import HelixKit

@main
struct HelixApp: App {
    @State private var store: SessionStore
    private let updaterController: SPUStandardUpdaterController

    static let defaultCLIPath = "/opt/homebrew/bin/mutagen"

    init() {
        let path = UserDefaults.standard.string(forKey: "cliPath") ?? Self.defaultCLIPath
        let cli = CLI(executablePath: path)
        _store = State(initialValue: SessionStore(provider: cli))
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(store: store)
                .frame(width: 320, height: 400)
        } label: {
            MenuBarIcon(health: store.overallHealth)
        }
        .menuBarExtraStyle(.window)

        Window("Helix", id: "main") {
            MainWindow(store: store)
        }
        .defaultSize(width: 800, height: 560)
        .commands {
            SessionCommands(store: store)
        }

        Settings {
            SettingsView(store: store, updater: updaterController.updater)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updaterController.updater)
            }
        }
    }
}

// MARK: - Keyboard Commands

struct SessionCommands: Commands {
    let store: SessionStore
    @FocusedBinding(\.showCreateSync) var showCreateSync
    @FocusedBinding(\.showCreateForward) var showCreateForward

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Sync Session...") {
                showCreateSync = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(showCreateSync == nil)

            Button("New Forward Session...") {
                showCreateForward = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(showCreateForward == nil)

            Divider()

            Button("Refresh Sessions") {
                Task { await store.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

// MARK: - Focused Values

struct ShowCreateSyncKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct ShowCreateForwardKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var showCreateSync: Binding<Bool>? {
        get { self[ShowCreateSyncKey.self] }
        set { self[ShowCreateSyncKey.self] = newValue }
    }

    var showCreateForward: Binding<Bool>? {
        get { self[ShowCreateForwardKey.self] }
        set { self[ShowCreateForwardKey.self] = newValue }
    }
}
