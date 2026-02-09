// ABOUTME: 4-step wizard for creating a new sync session.
// ABOUTME: Steps: Endpoints -> Mode -> Options -> Review with CLI command preview.

import SwiftUI
import HelixKit

struct CreateSyncView: View {
    let store: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0

    // Step 1: Endpoints
    @State private var sessionName = ""
    @State private var alphaTransport: TransportType = .local
    @State private var alphaPath = ""
    @State private var alphaHost = ""
    @State private var alphaUser = ""
    @State private var alphaPort = ""
    @State private var alphaContainer = ""
    @State private var betaTransport: TransportType = .ssh
    @State private var betaPath = ""
    @State private var betaHost = ""
    @State private var betaUser = ""
    @State private var betaPort = ""
    @State private var betaContainer = ""

    // Step 2: Mode
    @State private var syncMode = "two-way-safe"

    // Step 3: Options
    @State private var ignoreInput = ""
    @State private var ignoreVCS = false
    @State private var symlinkMode = "portable"
    @State private var compression = "none"
    @State private var watchMode = "portable"
    @State private var stageMode = "mutagen"
    @State private var createPaused = false

    // Step 4: Review
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Divider()

            TabView(selection: $step) {
                endpointsStep.tag(0)
                modeStep.tag(1)
                optionsStep.tag(2)
                reviewStep.tag(3)
            }
            .tabViewStyle(.automatic)

            Divider()
            navigationButtons
        }
        .frame(width: 560, height: 520)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { i in
                StepDot(
                    number: i + 1,
                    label: stepLabels[i],
                    isActive: step == i,
                    isCompleted: step > i
                )
                if i < 3 {
                    Rectangle()
                        .fill(step > i ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var stepLabels: [String] {
        ["Endpoints", "Mode", "Options", "Review"]
    }

    // MARK: - Step 1: Endpoints

    private var endpointsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Session Name (optional)", text: $sessionName)
                    .textFieldStyle(.roundedBorder)

                EndpointPicker(
                    label: "Alpha (Source)",
                    transport: $alphaTransport,
                    path: $alphaPath,
                    host: $alphaHost,
                    user: $alphaUser,
                    port: $alphaPort,
                    container: $alphaContainer
                )

                EndpointPicker(
                    label: "Beta (Destination)",
                    transport: $betaTransport,
                    path: $betaPath,
                    host: $betaHost,
                    user: $betaUser,
                    port: $betaPort,
                    container: $betaContainer
                )
            }
            .padding()
        }
    }

    // MARK: - Step 2: Mode

    private var modeStep: some View {
        ScrollView {
            SyncModePicker(selectedMode: $syncMode)
                .padding()
        }
    }

    // MARK: - Step 3: Options

    private var optionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SyncOptionsForm(
                    ignoreInput: $ignoreInput,
                    ignoreVCS: $ignoreVCS,
                    symlinkMode: $symlinkMode,
                    compression: $compression,
                    watchMode: $watchMode,
                    stageMode: $stageMode
                )

                Toggle("Create session paused", isOn: $createPaused)
            }
            .padding()
        }
    }

    // MARK: - Step 4: Review

    private var reviewStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    if !sessionName.isEmpty {
                        GridRow {
                            Text("Name").foregroundStyle(.secondary)
                            Text(sessionName)
                        }
                    }
                    GridRow {
                        Text("Alpha").foregroundStyle(.secondary)
                        Text(alphaEndpoint.formatted).monospaced()
                    }
                    GridRow {
                        Text("Beta").foregroundStyle(.secondary)
                        Text(betaEndpoint.formatted).monospaced()
                    }
                    GridRow {
                        Text("Mode").foregroundStyle(.secondary)
                        Text(syncMode)
                    }
                    if !ignorePaths.isEmpty {
                        GridRow {
                            Text("Ignore").foregroundStyle(.secondary)
                            Text(ignorePaths.joined(separator: ", ")).monospaced()
                        }
                    }
                }
                .font(.caption)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CLI Command")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(commandPreview, forType: .string)
                        }
                        .controlSize(.mini)
                    }

                    Text(commandPreview)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if step > 0 {
                Button("Back") {
                    withAnimation { step -= 1 }
                }
            }

            if step < 3 {
                Button("Next") {
                    withAnimation { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
            } else {
                Button("Create") {
                    Task { await createSession() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating)
            }
        }
        .padding()
    }

    private var canAdvance: Bool {
        switch step {
        case 0:
            return alphaEndpointPicker.isValid && betaEndpointPicker.isValid
        default:
            return true
        }
    }

    // MARK: - Data Assembly

    private var alphaEndpointPicker: EndpointPicker {
        EndpointPicker(
            label: "Alpha",
            transport: .constant(alphaTransport),
            path: .constant(alphaPath),
            host: .constant(alphaHost),
            user: .constant(alphaUser),
            port: .constant(alphaPort),
            container: .constant(alphaContainer)
        )
    }

    private var betaEndpointPicker: EndpointPicker {
        EndpointPicker(
            label: "Beta",
            transport: .constant(betaTransport),
            path: .constant(betaPath),
            host: .constant(betaHost),
            user: .constant(betaUser),
            port: .constant(betaPort),
            container: .constant(betaContainer)
        )
    }

    private var alphaEndpoint: EndpointURL {
        alphaEndpointPicker.endpointURL
    }

    private var betaEndpoint: EndpointURL {
        betaEndpointPicker.endpointURL
    }

    private var ignorePaths: [String] {
        ignoreInput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var options: SyncCreateOptions {
        var opts = SyncCreateOptions()
        opts.name = sessionName.isEmpty ? nil : sessionName
        opts.mode = syncMode
        opts.paused = createPaused
        opts.ignorePaths = ignorePaths
        opts.ignoreVCS = ignoreVCS
        if symlinkMode != "portable" { opts.symlinkMode = symlinkMode }
        if compression != "none" { opts.compression = compression }
        if watchMode != "portable" { opts.watchMode = watchMode }
        if stageMode != "mutagen" { opts.stageMode = stageMode }
        return opts
    }

    private var commandPreview: String {
        options.commandPreview(alpha: alphaEndpoint.formatted, beta: betaEndpoint.formatted)
    }

    private func createSession() async {
        isCreating = true
        await store.createSync(
            options: options,
            alpha: alphaEndpoint.formatted,
            beta: betaEndpoint.formatted
        )
        isCreating = false
        if store.lastError == nil {
            dismiss()
        }
    }
}

// MARK: - Supporting Views

private struct StepDot: View {
    let number: Int
    let label: String
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : (isCompleted ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.3)))
                    .frame(width: 24, height: 24)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

