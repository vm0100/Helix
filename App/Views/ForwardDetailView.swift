// ABOUTME: Detailed view for a forward session showing source and destination endpoints.
// ABOUTME: Provides action buttons for pause/resume and terminate.

import SwiftUI
import HelixKit

struct ForwardDetailView: View {
    let session: ForwardSession
    let store: SessionStore
    @State private var showTerminateConfirmation = false
    @State private var showSocket = false
    @State private var showDangerZone = false
    @State private var actionInProgress: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                endpointsSection
                if let socket = session.socket, socket.overwriteMode != nil {
                    socketSection(socket)
                }
                dangerZone
            }
            .padding()
        }
        .navigationTitle(session.name ?? session.identifier)
        .confirmationDialog(
            "Terminate Session?",
            isPresented: $showTerminateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Terminate", role: .destructive) {
                Task { await store.terminateForward(session.identifier) }
            }
        } message: {
            Text("This permanently removes the forward session. It cannot be undone.")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.name ?? session.identifier)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()

                HStack(spacing: 8) {
                    if actionInProgress != nil {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if session.paused {
                        Button("Resume") {
                            Task { await runAction("resume") { await store.resumeForward(session.identifier) } }
                        }
                        .disabled(actionInProgress != nil)
                    } else {
                        Button("Pause") {
                            Task { await runAction("pause") { await store.pauseForward(session.identifier) } }
                        }
                        .disabled(actionInProgress != nil)
                    }
                }
                .controlSize(.small)
            }

            HStack {
                Circle()
                    .fill(session.source.connected == true ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(session.paused ? "Paused" : (session.source.connected == true ? "Connected" : "Disconnected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Label("Forward", systemImage: "network")
                Label(session.creationTime.prefix(10).description, systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let labels = session.labels, !labels.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        Text("\(key): \(value)")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func runAction(_ name: String, _ action: () async -> Void) async {
        actionInProgress = name
        await action()
        actionInProgress = nil
    }

    private var endpointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Endpoints")
                .font(.headline)

            HStack(alignment: .top, spacing: 0) {
                ForwardEndpointCard(label: "Source", endpoint: session.source, address: session.sourceEndpoint)

                VStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                    Text("Forward")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
                .frame(width: 56)
                .padding(.top, 16)

                ForwardEndpointCard(label: "Destination", endpoint: session.destination, address: session.destinationEndpoint)
            }
        }
    }

    private func socketSection(_ socket: SocketConfig) -> some View {
        DisclosureGroup(isExpanded: $showSocket) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if let mode = socket.overwriteMode {
                    GridRow {
                        Text("Overwrite Mode").foregroundStyle(.secondary)
                        Text(mode)
                    }
                }
                if let owner = socket.owner {
                    GridRow {
                        Text("Owner").foregroundStyle(.secondary)
                        Text(owner)
                    }
                }
                if let group = socket.group {
                    GridRow {
                        Text("Group").foregroundStyle(.secondary)
                        Text(group)
                    }
                }
            }
            .font(.caption)
            .padding(.top, 4)
        } label: {
            Text("Socket Configuration")
                .contentShape(Rectangle())
                .onTapGesture { showSocket.toggle() }
        }
    }

    private var dangerZone: some View {
        DisclosureGroup(isExpanded: $showDangerZone) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Terminate Session")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Permanently remove this forward session.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Terminate", role: .destructive) {
                    showTerminateConfirmation = true
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        } label: {
            Text("Danger Zone")
                .contentShape(Rectangle())
                .onTapGesture { showDangerZone.toggle() }
        }
        .foregroundStyle(.red)
    }
}

private struct ForwardEndpointCard: View {
    let label: String
    let endpoint: ForwardEndpoint
    let address: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(endpoint.connected == true ? .green : .red)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(endpoint.connected == true ? "Connected" : "Disconnected")
            }

            LabeledContent("Transport", value: endpoint.protocol_)
            if let user = endpoint.user {
                LabeledContent("User", value: user)
            }
            if let host = endpoint.host {
                LabeledContent("Host", value: host)
            }
            if let addr = address {
                LabeledContent("Address") {
                    Text(addr)
                        .monospaced()
                        .lineLimit(1)
                }
            }
        }
        .font(.caption)
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
