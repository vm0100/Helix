// ABOUTME: Reusable endpoint configuration component for sync/forward session creation.
// ABOUTME: Provides Local/SSH/Docker transport selection with context-appropriate fields.

import SwiftUI
import MutagenKit

enum TransportType: String, CaseIterable {
    case local = "Local"
    case ssh = "SSH"
    case docker = "Docker"
}

struct EndpointPicker: View {
    let label: String
    @Binding var transport: TransportType
    @Binding var path: String
    @Binding var host: String
    @Binding var user: String
    @Binding var port: String
    @Binding var container: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.headline)

            Picker("Transport", selection: $transport) {
                ForEach(TransportType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            switch transport {
            case .local:
                localFields
            case .ssh:
                sshFields
            case .docker:
                dockerFields
            }
        }
    }

    var endpointURL: EndpointURL {
        switch transport {
        case .local:
            return .local(path: path)
        case .ssh:
            let portNum = Int(port)
            return .ssh(
                user: user.isEmpty ? nil : user,
                host: host,
                port: portNum,
                path: path
            )
        case .docker:
            return .docker(container: container, path: path)
        }
    }

    var isValid: Bool {
        switch transport {
        case .local:
            return !path.isEmpty
        case .ssh:
            return !host.isEmpty && !path.isEmpty
        case .docker:
            return !container.isEmpty && !path.isEmpty
        }
    }

    // MARK: - Field Groups

    private var localFields: some View {
        HStack {
            TextField("Path", text: $path)
                .textFieldStyle(.roundedBorder)
            Button("Browse...") {
                browseForFolder()
            }
        }
    }

    private var sshFields: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("User", text: $user)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                TextField("Host", text: $host)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $port)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 60)
            }
            TextField("Remote Path", text: $path)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var dockerFields: some View {
        VStack(spacing: 8) {
            TextField("Container Name or ID", text: $container)
                .textFieldStyle(.roundedBorder)
            TextField("Container Path", text: $path)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - File Browsing

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory to sync"

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}
