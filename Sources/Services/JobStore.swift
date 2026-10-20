import AppKit
import Foundation

/// A property list file shown in the sidebar.
struct AgentFile: Identifiable, Hashable {
    let url: URL
    let label: String
    let readOnly: Bool
    var id: URL { url }
}

/// An alert request published by the store and presented by the main window.
struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var confirmTitle: String?
    var destructive = false
    var action: (() -> Void)?
}

/// Wrapper so a log file URL can drive a sheet.
struct LogTarget: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Central app state: the agent list, the job being edited, and all file / launchctl actions.
@MainActor
final class JobStore: ObservableObject {
    @Published var agents: [AgentFile] = []
    @Published var statuses: [String: JobStatus] = [:]
    @Published var selection: URL?
    @Published var draft: LaunchJob?
    @Published var draftURL: URL?
    @Published var readOnly = false
    @Published var changedOnDisk = false
    @Published var statusText = "Ready."
    @Published var statusFailed = false
    @Published var alert: AppAlert?
    @Published var showTemplates = false
    @Published var logTarget: LogTarget?
    @Published var printOutput = ""

    private var loadedDate: Date?
    private var originalLabel: String?

    static let userAgentsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    static let globalAgentsDir = URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true)

    static var defaultPrefix: String {
        let user = NSUserName().lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return user.isEmpty ? "com.example" : "com.\(user)"
    }

    private var createdByApp: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "createdPaths") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "createdPaths") }
    }

    func isLoaded(_ label: String?) -> Bool { label.map { statuses[$0] != nil } ?? false }

    // MARK: Listing

    func reloadList() async {
        var list = Self.scan(Self.userAgentsDir, readOnly: false)
        if UserDefaults.standard.bool(forKey: "showThirdParty") {
            list += Self.scan(Self.globalAgentsDir, readOnly: true)
        }
        agents = list.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        await refreshStatus()
    }

    func refreshStatus() async { statuses = await Launchctl.list() }

    private static func scan(_ dir: URL, readOnly: Bool) -> [AgentFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "plist" }.map { url in
            let label = readDict(url)?["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
            return AgentFile(url: url, label: label, readOnly: readOnly)
        }
    }

    static func readDict(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func modDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    // MARK: Editing

    func open(_ url: URL?) {
        guard let url else { return }
        guard let dict = Self.readDict(url) else {
            draft = nil
            report(false, "Could not read \(url.lastPathComponent): it is not a valid property list.")
            return
        }
        let job = LaunchJob(dictionary: dict)
        draft = job
        draftURL = url
        readOnly = agents.first { $0.url == url }?.readOnly ?? !url.path.hasPrefix(Self.userAgentsDir.path)
        originalLabel = job.label
        loadedDate = Self.modDate(url)
        changedOnDisk = false
        printOutput = ""
    }

    func newJob(_ template: JobTemplate, prefix: String) {
        selection = nil
        draft = template.make(prefix: prefix)
        draftURL = nil
        readOnly = false
        originalLabel = nil
        loadedDate = nil
        changedOnDisk = false
        printOutput = ""
        report(true, "New job from “\(template.rawValue)”. Edit it, then press Save.")
    }

    func checkDiskChanges() {
        guard let url = draftURL, let loaded = loadedDate, !changedOnDisk else { return }
        if Self.modDate(url).map({ $0 > loaded }) ?? true { changedOnDisk = true }
    }

    func ignoreDiskChange() {
        changedOnDisk = false
        if let url = draftURL { loadedDate = Self.modDate(url) ?? Date() }
    }

    func chooseProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Choose an executable script or binary for this job"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft?.program = url.path
        if let error = draft?.programError { report(false, "\(url.lastPathComponent): \(error). Try `chmod +x` on it.") }
    }

    func save(force: Bool = false) {
        guard let job = draft, !readOnly else { return }
        if let error = job.labelError ?? job.intervalError ?? job.calendarError {
            alert = AppAlert(title: "Cannot save", message: error)
            return
        }
        if let error = job.programError {
            alert = AppAlert(title: "Program problem", message: "\(error). Choose an executable file to run.",
                             confirmTitle: "Choose Program…", action: { [weak self] in self?.chooseProgram() })
            return
        }
        let target = Self.userAgentsDir.appendingPathComponent("\(job.label).plist")
        let fm = FileManager.default
        if draftURL != nil, draftURL != target, isLoaded(originalLabel) {
            alert = AppAlert(title: "Unload first", message: "Unload “\(originalLabel ?? "")” before changing its label.")
            return
        }
        if !force, fm.fileExists(atPath: target.path), draftURL != target || !createdByApp.contains(target.path) {
            alert = AppAlert(title: "Overwrite \(target.lastPathComponent)?",
                             message: "This file was not created by LaunchdLens. Unknown keys are preserved, but comments and formatting will be lost.",
                             confirmTitle: "Overwrite", destructive: true, action: { [weak self] in self?.save(force: true) })
            return
        }
        do {
            try fm.createDirectory(at: Self.userAgentsDir, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: job.dictionary, format: .xml, options: 0)
            try data.write(to: target, options: .atomic)
            if let old = draftURL, old != target, old.path.hasPrefix(Self.userAgentsDir.path) {
                try? fm.removeItem(at: old)
            }
            createdByApp.insert(target.path)
            draftURL = target
            originalLabel = job.label
            loadedDate = Self.modDate(target)
            changedOnDisk = false
            report(true, "Saved \(target.path)." + (isLoaded(job.label) ? " Unload and Load again to apply changes." : ""))
            Task {
                await reloadList()
                selection = target
            }
        } catch {
            report(false, "Save failed: \(error.localizedDescription)")
        }
    }

    // MARK: launchctl actions

    func load() async {
        guard let url = draftURL else { return report(false, "Save the job before loading it.") }
        report("Load", await Launchctl.bootstrap(url))
        await refreshStatus()
    }

    func unload() async {
        guard let label = originalLabel else { return report(false, "This job is not saved yet.") }
        report("Unload", await Launchctl.bootout(label))
        await refreshStatus()
    }

    func runNow() async {
        guard let label = originalLabel else { return report(false, "Save and load the job before running it.") }
        guard isLoaded(label) else { return report(false, "“\(label)” is not loaded. Press Load first.") }
        report("Run Now", await Launchctl.kickstart(label))
        await refreshStatus()
    }

    func printStatus() async {
        guard let label = originalLabel else { printOutput = "Save and load the job to inspect it."; return }
        let result = await Launchctl.printJob(label)
        printOutput = result.ok ? result.output : "launchctl print failed (exit \(result.code)):\n\(result.output)"
    }

    func reveal() {
        guard let url = draftURL else { return report(false, "Save the job first.") }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func showLog() {
        guard let job = draft else { return }
        let path = job.standardOutPath.isEmpty ? job.standardErrorPath : job.standardOutPath
        guard !path.isEmpty else { return report(false, "Set a Standard output path to see this job's log.") }
        logTarget = LogTarget(url: URL(fileURLWithPath: path))
    }

    func delete() {
        guard let url = draftURL, let label = originalLabel, !readOnly else { return }
        let loadedNote = isLoaded(label) ? "The job is loaded and will be unloaded first. " : ""
        alert = AppAlert(title: "Delete “\(label)”?", message: loadedNote + "The file will be moved to the Trash.",
                         confirmTitle: "Delete", destructive: true,
                         action: { [weak self] in Task { await self?.performDelete(url: url, label: label) } })
    }

    private func performDelete(url: URL, label: String) async {
        if isLoaded(label) {
            let result = await Launchctl.bootout(label)
            guard result.ok else { return report("Unload before delete", result) }
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            draft = nil
            draftURL = nil
            selection = nil
            report(true, "Unloaded and moved \(url.lastPathComponent) to the Trash.")
        } catch {
            report(false, "Delete failed: \(error.localizedDescription)")
        }
        await reloadList()
    }

    // MARK: Status bar

    func report(_ ok: Bool, _ text: String) {
        statusFailed = !ok
        statusText = text
    }

    private func report(_ action: String, _ result: Launchctl.Result) {
        let out = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.ok {
            report(true, "\(action) succeeded." + (out.isEmpty ? "" : " \(out)"))
        } else {
            report(false, "\(action) failed (launchctl exit \(result.code)): \(out.isEmpty ? "no output" : out)")
        }
    }
}
