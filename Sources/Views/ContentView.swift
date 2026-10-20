import SwiftUI

/// Main window: agent list on the left, editor or empty state on the right, status bar below.
struct ContentView: View {
    @EnvironmentObject private var store: JobStore
    @AppStorage("labelPrefix") private var labelPrefix = JobStore.defaultPrefix
    @AppStorage("showThirdParty") private var showThirdParty = false
    @State private var search = ""

    private var filtered: [AgentFile] {
        search.isEmpty ? store.agents : store.agents.filter { $0.label.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $store.selection) { agent in
                AgentRow(agent: agent, status: store.statuses[agent.label]).tag(agent.url)
            }
            .overlay {
                if filtered.isEmpty {
                    Text(search.isEmpty ? "No launch agents yet" : "No matches").foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Per-user launch agents only. System-wide daemons need admin rights and are out of scope.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Support / Donate ❤️") { openDonation() }.controlSize(.small)
                }
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 270)
        } detail: {
            if store.draft != nil { JobEditorView() } else { EmptyStateView() }
        }
        .searchable(text: $search, prompt: "Search labels")
        .toolbar {
            ToolbarItemGroup {
                Button { store.showTemplates = true } label: { Label("New Job", systemImage: "plus") }
                    .help("New job from a template (⌘N)")
                Button { Task { await store.reloadList() } } label: { Label("Reload List", systemImage: "arrow.clockwise") }
                    .help("Reload the agent list and status")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .onChange(of: store.selection) { _, url in store.open(url) }
        .onChange(of: showThirdParty) { _, _ in Task { await store.reloadList() } }
        .sheet(isPresented: $store.showTemplates) { TemplatePicker(prefix: labelPrefix) }
        .sheet(item: $store.logTarget) { LogView(url: $0.url) }
        .alert(store.alert?.title ?? "", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } }),
               presenting: store.alert) { alert in
            if let title = alert.confirmTitle {
                Button(title, role: alert.destructive ? .destructive : nil) { alert.action?() }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: { Text($0.message) }
        .task {
            await store.reloadList()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                store.checkDiskChanges()
                await store.refreshStatus()
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: store.statusFailed ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(store.statusFailed ? .red : .secondary)
            Text(store.statusText)
                .font(.callout)
                .foregroundStyle(store.statusFailed ? .red : .primary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
    }
}

/// Sidebar row with a status dot: green running, blue loaded, red failed last run, gray not loaded.
struct AgentRow: View {
    let agent: AgentFile
    let status: JobStatus?

    private var color: Color {
        guard let status else { return .gray }
        if status.pid != nil { return .green }
        return (status.lastExit ?? 0) == 0 ? .blue : .red
    }

    private var caption: String {
        guard let status else { return "Not loaded" }
        if let pid = status.pid { return "Running · PID \(pid)" }
        return "Loaded · last exit \(status.lastExit.map(String.init) ?? "–")"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.label).lineLimit(1).truncationMode(.middle)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if agent.readOnly { Image(systemName: "lock.fill").foregroundStyle(.secondary).help("Read-only third-party agent") }
        }
    }
}

/// Shown when no job is selected: explains launch agents and offers a template.
struct EmptyStateView: View {
    @EnvironmentObject private var store: JobStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.badge.checkmark").font(.system(size: 52)).foregroundStyle(.tint)
            Text("Launch agents, without the XML").font(.title2.bold())
            Text("A launch agent is a small property list in ~/Library/LaunchAgents that tells macOS to run something for you: a script on a schedule, an app at login, a command when a folder changes, or a process kept alive. Per-user agents need no admin rights.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
            Button("Create a Job from a Template…") { store.showTemplates = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(40)
    }
}

/// Sheet offering the four starting templates.
struct TemplatePicker: View {
    @EnvironmentObject private var store: JobStore
    @Environment(\.dismiss) private var dismiss
    let prefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Job").font(.title2.bold())
            ForEach(JobTemplate.allCases) { template in
                Button {
                    store.newJob(template, prefix: prefix)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: template.symbol).font(.title2).frame(width: 34)
                        VStack(alignment: .leading) {
                            Text(template.rawValue).font(.headline)
                            Text(template.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            }
            HStack { Spacer(); Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(20)
        .frame(width: 440)
    }
}
