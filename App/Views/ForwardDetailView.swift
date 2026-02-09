// ABOUTME: Detailed view for a forward session showing source and destination endpoints.
// ABOUTME: Provides action buttons for pause/resume and terminate.

import SwiftUI
import HelixKit

struct ForwardDetailView: View {
    let session: ForwardSession
    let store: SessionStore
    @State private var showTerminateConfirmation = false

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
                    if session.paused {
                        Button("Resume") {
                            Task { await store.resumeForward(session.identifier) }
                        }
                    } else {
                        Button("Pause") {
                            Task { await store.pauseForward(session.identifier) }
                        }
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
        }
    }

    private var endpointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Endpoints")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                ForwardEndpointCard(label: "Source", endpoint: session.source, address: session.sourceEndpoint)
                ForwardEndpointCard(label: "Destination", endpoint: session.destination, address: session.destinationEndpoint)
            }
        }
    }

    private func socketSection(_ socket: SocketConfig) -> some View {
        DisclosureGroup("Socket Configuration") {
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
        }
    }

    private var dangerZone: some View {
        DisclosureGroup("Danger Zone") {
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
