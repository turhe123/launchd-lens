import Foundation

/// Runtime status of a job as reported by `launchctl list`.
struct JobStatus {
    let pid: Int?
    let lastExit: Int?
}

/// Thin async wrapper around `/bin/launchctl` for the current user's gui domain.
enum Launchctl {
    /// Exit code plus combined stdout/stderr of one launchctl invocation.
    struct Result {
        let code: Int32
        let output: String
        var ok: Bool { code == 0 }
    }

    static var domain: String { "gui/\(getuid())" }

    static func run(_ args: [String]) async -> Result {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do { try process.run() } catch {
                return Result(code: -1, output: error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Result(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }

    /// Parses `launchctl list` ("PID<TAB>Status<TAB>Label") into a label-keyed map.
    static func list() async -> [String: JobStatus] {
        let result = await run(["list"])
        var statuses: [String: JobStatus] = [:]
        for line in result.output.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            statuses[String(cols[2])] = JobStatus(pid: Int(cols[0]), lastExit: Int(cols[1]))
        }
        return statuses
    }

    static func bootstrap(_ url: URL) async -> Result { await run(["bootstrap", domain, url.path]) }
    static func bootout(_ label: String) async -> Result { await run(["bootout", "\(domain)/\(label)"]) }
    static func kickstart(_ label: String) async -> Result { await run(["kickstart", "\(domain)/\(label)"]) }
    static func printJob(_ label: String) async -> Result { await run(["print", "\(domain)/\(label)"]) }
}
