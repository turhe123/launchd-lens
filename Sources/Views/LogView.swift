import AppKit
import SwiftUI

/// Scrolling tail of a job's output file, refreshed every two seconds.
struct LogView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(url.path).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            Text("Showing the last 64 KB · refreshes every 2 seconds").font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 680, minHeight: 440)
        .task {
            while !Task.isCancelled {
                text = Self.tail(url)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    static func tail(_ url: URL, maxBytes: UInt64 = 64_000) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "The log file does not exist yet:\n\(url.path)\n\nIt appears after the job writes output."
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > maxBytes ? size - maxBytes : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return data.isEmpty ? "(log is empty)" : String(decoding: data, as: UTF8.self)
    }
}
