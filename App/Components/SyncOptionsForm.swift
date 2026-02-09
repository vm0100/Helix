// ABOUTME: Form for sync session options (ignore, symlink, compression, watch, staging).
// ABOUTME: Extracted for reuse in both CreateSyncView and EditSyncConfigView.

import SwiftUI

struct SyncOptionsForm: View {
    @Binding var ignoreInput: String
    @Binding var ignoreVCS: Bool
    @Binding var symlinkMode: String
    @Binding var compression: String
    @Binding var watchMode: String
    @Binding var stageMode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup("Ignore Rules") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("One pattern per line. Uses gitignore-style syntax.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $ignoreInput)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                        .border(Color.secondary.opacity(0.3))
                    Toggle("Ignore VCS directories (.git, .svn, etc.)", isOn: $ignoreVCS)
                }
                .padding(.top, 4)
            }

            DisclosureGroup("Symlink Handling") {
                Picker("Mode", selection: $symlinkMode) {
                    Text("Portable (safe relative links)").tag("portable")
                    Text("Ignore (skip all symlinks)").tag("ignore")
                    Text("POSIX Raw (all links, POSIX only)").tag("posix-raw")
                }
                .padding(.top, 4)
            }

            DisclosureGroup("Compression") {
                Picker("Algorithm", selection: $compression) {
                    Text("None").tag("none")
                    Text("Deflate (zlib)").tag("deflate")
                    Text("Zstandard (faster)").tag("zstandard")
                }
                .padding(.top, 4)
            }

            DisclosureGroup("Watch Mode") {
                Picker("Mode", selection: $watchMode) {
                    Text("Portable (automatic)").tag("portable")
                    Text("Force Poll (unreliable FS)").tag("force-poll")
                    Text("No Watch (manual flush only)").tag("no-watch")
                }
                .padding(.top, 4)
            }

            DisclosureGroup("Staging") {
                Picker("Mode", selection: $stageMode) {
                    Text("Mutagen (in ~/.mutagen)").tag("mutagen")
                    Text("Neighboring (beside sync root)").tag("neighboring")
                    Text("Internal (inside sync root)").tag("internal")
                }
                .padding(.top, 4)
            }
        }
    }
}
