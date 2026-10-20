import SwiftUI

/// Settings: default label prefix, third-party agent visibility and the donation link.
struct SettingsView: View {
    @AppStorage("labelPrefix") private var labelPrefix = JobStore.defaultPrefix
    @AppStorage("showThirdParty") private var showThirdParty = false

    var body: some View {
        Form {
            Section("New jobs") {
                TextField("Default label prefix", text: $labelPrefix)
                HStack {
                    Text("Templates create labels like \(labelPrefix).backup").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { labelPrefix = JobStore.defaultPrefix }.controlSize(.small)
                }
            }
            Section("Agent list") {
                Toggle("Also show read-only third-party agents (/Library/LaunchAgents)", isOn: $showThirdParty)
            }
            Section("Scope") {
                Text("LaunchdLens manages per-user launch agents in ~/Library/LaunchAgents. System-wide daemons need a privileged helper and are intentionally out of scope.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Button("Support / Donate ❤️") { openDonation() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
