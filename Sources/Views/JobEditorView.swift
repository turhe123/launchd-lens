import SwiftUI

/// Detail pane: action buttons, then the validated form, raw property list or `launchctl print` output.
struct JobEditorView: View {
    @EnvironmentObject private var store: JobStore
    @State private var tab = 0
    @State private var preset = SchedulePreset.weekdays
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var weekday = 1
    @State private var day = 1

    private var job: Binding<LaunchJob> {
        Binding(get: { store.draft ?? LaunchJob() }, set: { store.draft = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.changedOnDisk {
                HStack {
                    Image(systemName: "exclamationmark.arrow.circlepath")
                    Text("This file changed on disk.")
                    Spacer()
                    Button("Reload") { store.open(store.draftURL) }
                    Button("Keep My Edits") { store.ignoreDiskChange() }
                }
                .padding(8).background(.yellow.opacity(0.25))
            }
            actionBar
            Picker("View", selection: $tab) {
                Text("Editor").tag(0)
                Text("Property List").tag(1)
                Text("launchctl print").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal).padding(.bottom, 6)
            switch tab {
            case 1: monospaced(job.wrappedValue.xmlString)
            case 2:
                monospaced(store.printOutput.isEmpty ? "Loading…" : store.printOutput)
                    .task(id: store.draftURL) { await store.printStatus() }
            default: form
            }
        }
        .navigationTitle(job.wrappedValue.label.isEmpty ? "New Job" : job.wrappedValue.label)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("Save", systemImage: "square.and.arrow.down") { store.save() }.disabled(store.readOnly)
            Button("Load", systemImage: "play.circle") { Task { await store.load() } }.disabled(store.draftURL == nil)
            Button("Unload", systemImage: "stop.circle") { Task { await store.unload() } }.disabled(store.draftURL == nil)
            Button("Run Now", systemImage: "bolt.fill") { Task { await store.runNow() } }.disabled(store.draftURL == nil)
            Divider().frame(height: 18)
            Button("Reveal in Finder", systemImage: "folder") { store.reveal() }.disabled(store.draftURL == nil)
            Button("Show Log", systemImage: "doc.text.magnifyingglass") { store.showLog() }
            Spacer()
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete() }
                .disabled(store.readOnly || store.draftURL == nil)
        }
        .labelStyle(.titleAndIcon)
        .padding(10)
    }

    private var form: some View {
        let j = job.wrappedValue
        return Form {
            if store.readOnly {
                Label("Read-only third-party agent. It can be loaded, run and inspected, but not edited.", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            Section("Program") {
                field("Label", j.labelError) { TextField("com.you.job", text: job.label) }
                field("Program", j.programError) {
                    HStack {
                        TextField("/path/to/executable", text: job.program)
                        Button("Choose…") { store.chooseProgram() }
                    }
                }
                field("Arguments", nil) {
                    TextEditor(text: lines(job.arguments)).font(.body.monospaced()).frame(height: 56)
                    Text("One argument per line.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("When to run") {
                Toggle("Run at load", isOn: job.runAtLoad)
                Toggle("Keep alive", isOn: job.keepAlive)
                field("Start interval (seconds)", j.intervalError) { TextField("none", text: number(job.startInterval)) }
                field("Watch paths", nil) {
                    TextEditor(text: lines(job.watchPaths)).font(.body.monospaced()).frame(height: 40)
                }
                calendarEditor(j)
                Label(j.scheduleSummary, systemImage: "text.bubble").foregroundStyle(.secondary)
            }
            Section("Environment") {
                TextField("Working directory", text: job.workingDirectory)
                TextField("Standard output path", text: job.standardOutPath)
                TextField("Standard error path", text: job.standardErrorPath)
            }
        }
        .formStyle(.grouped)
        .disabled(store.readOnly)
    }

    @ViewBuilder
    private func calendarEditor(_ j: LaunchJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calendar schedule")
                Spacer()
                Button("Add Entry", systemImage: "plus") { store.draft?.calendar.append(CalendarEntry(minute: 0, hour: 9)) }
            }
            HStack {
                Picker("Quick", selection: $preset) { ForEach(SchedulePreset.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 200)
                DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden()
                if preset == .weekly {
                    Picker("", selection: $weekday) { ForEach(1...7, id: \.self) { Text(LaunchJob.weekdayNames[$0]).tag($0) } }
                        .labelsHidden().frame(width: 120)
                }
                if preset == .monthly { Stepper("Day \(day)", value: $day, in: 1...31) }
                Button("Apply") {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                    store.draft?.calendar = preset.entries(hour: parts.hour ?? 9, minute: parts.minute ?? 0, weekday: weekday, day: day)
                }
            }
            ForEach(job.calendar) { $entry in
                HStack {
                    TextField("Minute", text: number($entry.minute))
                    TextField("Hour", text: number($entry.hour))
                    TextField("Weekday", text: number($entry.weekday))
                    TextField("Day", text: number($entry.day))
                    Button { store.draft?.calendar.removeAll { $0.id == entry.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
                .textFieldStyle(.roundedBorder)
            }
            if !j.calendar.isEmpty {
                Text("Empty field = any. Weekday 0 or 7 is Sunday.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = j.calendarError { errorNote(error) }
        }
    }

    // MARK: Helpers

    private func field<Content: View>(_ title: String, _ error: String?, @ViewBuilder content: () -> Content) -> some View {
        LabeledContent(title) {
            VStack(alignment: .leading, spacing: 3) {
                content()
                if let error { errorNote(error) }
            }
        }
    }

    private func errorNote(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.red)
    }

    private func monospaced(_ text: String) -> some View {
        ScrollView {
            Text(text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
        }
    }

    private func lines(_ binding: Binding<[String]>) -> Binding<String> {
        Binding(get: { binding.wrappedValue.joined(separator: "\n") },
                set: { binding.wrappedValue = $0.components(separatedBy: "\n").filter { !$0.isEmpty } })
    }

    private func number(_ binding: Binding<Int?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue.map(String.init) ?? "" },
                set: { binding.wrappedValue = Int($0.trimmingCharacters(in: .whitespaces)) })
    }
}
