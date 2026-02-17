// ABOUTME: Editable key-value tag input with pill display and add/remove support.
// ABOUTME: Used in session creation, editing, and detail views to manage mutagen labels.

import SwiftUI

struct LabelEditor: View {
    @Binding var labels: [String: String]
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !labels.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(spacing: 4) {
                            Text("\(key)=\(value)")
                                .font(.caption2)
                            Button {
                                labels.removeValue(forKey: key)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(key)")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("key=value", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addLabel() }
                Button {
                    addLabel()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!isInputValid)
            }
            .font(.caption)

            if let error = validationError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func addLabel() {
        guard isInputValid else { return }
        let parts = input.split(separator: "=", maxSplits: 1)
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        labels[key] = value
        input = ""
    }

    private var parsedKey: String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("=") else { return nil }
        let key = trimmed.split(separator: "=", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return key
    }

    private var isInputValid: Bool {
        guard let key = parsedKey, !key.isEmpty else { return false }
        return !labels.keys.contains(key)
    }

    private var validationError: String? {
        guard let key = parsedKey else { return nil }
        if key.isEmpty {
            return "Key cannot be empty"
        }
        if labels.keys.contains(key) {
            return "Key '\(key)' already exists"
        }
        return nil
    }
}
