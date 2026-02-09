// ABOUTME: Sparkle "Check for Updates" button that observes updater readiness.
// ABOUTME: Bridges SPUUpdater's KVO canCheckForUpdates into SwiftUI via Combine.

import Sparkle
import SwiftUI

final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var viewModel: UpdaterViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = UpdaterViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
