import Foundation

/// One `StartCalendarInterval` entry. A nil field means "any value".
struct CalendarEntry: Identifiable, Hashable {
    var id = UUID()
    var minute: Int?
    var hour: Int?
    var weekday: Int?
    var day: Int?

    init(minute: Int? = nil, hour: Int? = nil, weekday: Int? = nil, day: Int? = nil) {
        self.minute = minute; self.hour = hour; self.weekday = weekday; self.day = day
    }

    init(dictionary d: [String: Any]) {
        self.init(minute: d["Minute"] as? Int, hour: d["Hour"] as? Int,
                  weekday: d["Weekday"] as? Int, day: d["Day"] as? Int)
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let minute { d["Minute"] = minute }
        if let hour { d["Hour"] = hour }
        if let weekday { d["Weekday"] = weekday }
        if let day { d["Day"] = day }
        return d
    }
}

/// Editable model of a launch agent property list. Known keys are mapped to fields;
/// every other key is kept in `extra` so a round trip never drops data.
struct LaunchJob {
    var label = ""
    var program = ""
    var arguments: [String] = []
    var runAtLoad = false
    var keepAlive = false
    var startInterval: Int?
    var calendar: [CalendarEntry] = []
    var watchPaths: [String] = []
    var workingDirectory = ""
    var standardOutPath = ""
    var standardErrorPath = ""
    var extra: [String: Any] = [:]

    init() {}

    init(dictionary: [String: Any]) {
        var d = dictionary
        label = d.removeValue(forKey: "Label") as? String ?? ""
        let prog = d.removeValue(forKey: "Program") as? String
        let args = d.removeValue(forKey: "ProgramArguments") as? [String] ?? []
        program = prog ?? args.first ?? ""
        arguments = Array(args.dropFirst())
        runAtLoad = d.removeValue(forKey: "RunAtLoad") as? Bool ?? false
        if let keep = d["KeepAlive"] as? Bool { keepAlive = keep; d["KeepAlive"] = nil }
        startInterval = d.removeValue(forKey: "StartInterval") as? Int
        switch d.removeValue(forKey: "StartCalendarInterval") {
        case let one as [String: Any]: calendar = [CalendarEntry(dictionary: one)]
        case let many as [[String: Any]]: calendar = many.map(CalendarEntry.init(dictionary:))
        default: break
        }
        watchPaths = d.removeValue(forKey: "WatchPaths") as? [String] ?? []
        workingDirectory = d.removeValue(forKey: "WorkingDirectory") as? String ?? ""
        standardOutPath = d.removeValue(forKey: "StandardOutPath") as? String ?? ""
        standardErrorPath = d.removeValue(forKey: "StandardErrorPath") as? String ?? ""
        extra = d
    }

    var dictionary: [String: Any] {
        var d = extra
        d["Label"] = label
        d["ProgramArguments"] = [program] + arguments
        if runAtLoad { d["RunAtLoad"] = true }
        if keepAlive { d["KeepAlive"] = true }
        if let startInterval { d["StartInterval"] = startInterval }
        if calendar.count == 1 { d["StartCalendarInterval"] = calendar[0].dictionary }
        if calendar.count > 1 { d["StartCalendarInterval"] = calendar.map(\.dictionary) }
        if !watchPaths.isEmpty { d["WatchPaths"] = watchPaths }
        if !workingDirectory.isEmpty { d["WorkingDirectory"] = workingDirectory }
        if !standardOutPath.isEmpty { d["StandardOutPath"] = standardOutPath }
        if !standardErrorPath.isEmpty { d["StandardErrorPath"] = standardErrorPath }
        return d
    }

    var xmlString: String {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        else { return "Could not encode property list." }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Validation

    var labelError: String? {
        if label.isEmpty { return "Label is required" }
        let pattern = #"^[A-Za-z0-9-]+(\.[A-Za-z0-9_-]+)+$"#
        return label.range(of: pattern, options: .regularExpression) == nil
            ? "Use reverse-domain style, e.g. com.you.backup" : nil
    }

    var programError: String? {
        if program.isEmpty { return "Program path is required" }
        if !program.hasPrefix("/") { return "Use an absolute path (launchd does not expand ~)" }
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: program, isDirectory: &isDir) { return "File does not exist" }
        if isDir.boolValue || !FileManager.default.isExecutableFile(atPath: program) { return "File is not executable" }
        return nil
    }

    var intervalError: String? {
        if let s = startInterval, s <= 0 { return "Must be a positive number of seconds" }
        return nil
    }

    var calendarError: String? {
        func bad(_ v: Int?, _ r: ClosedRange<Int>) -> Bool { v.map { !r.contains($0) } ?? false }
        for e in calendar {
            if bad(e.minute, 0...59) { return "Minute must be 0–59" }
            if bad(e.hour, 0...23) { return "Hour must be 0–23" }
            if bad(e.weekday, 0...7) { return "Weekday must be 0–7 (0 and 7 are Sunday)" }
            if bad(e.day, 1...31) { return "Day must be 1–31" }
        }
        return nil
    }

    // MARK: Plain-language summary

    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var scheduleSummary: String {
        var parts: [String] = []
        if let s = startInterval, s > 0 {
            parts.append(s % 3600 == 0 ? "every \(s / 3600) hour(s)" : s % 60 == 0 ? "every \(s / 60) minute(s)" : "every \(s) seconds")
        }
        let sameTime = Set(calendar.map { [$0.hour ?? -1, $0.minute ?? -1] }).count == 1
        if calendar.count == 5, sameTime, Set(calendar.compactMap(\.weekday)) == [1, 2, 3, 4, 5],
           calendar.allSatisfy({ $0.day == nil }) {
            parts.append("every weekday " + Self.timeText(calendar[0]))
        } else {
            parts += calendar.map(Self.describe)
        }
        if runAtLoad { parts.append("when loaded (at login)") }
        if !watchPaths.isEmpty { parts.append("when \(watchPaths.count) watched path(s) change") }
        if keepAlive { parts.append("and is restarted whenever it exits") }
        return parts.isEmpty ? "Runs only when started manually." : "Runs " + parts.joined(separator: "; ") + "."
    }

    static func timeText(_ e: CalendarEntry) -> String {
        switch (e.hour, e.minute) {
        case let (h?, m?): return String(format: "at %02d:%02d", h, m)
        case let (h?, nil): return "every minute during hour \(h)"
        case let (nil, m?): return String(format: "every hour at :%02d", m)
        default: return "every minute"
        }
    }

    static func describe(_ e: CalendarEntry) -> String {
        var s = timeText(e)
        if let w = e.weekday, weekdayNames.indices.contains(w) { s += " on \(weekdayNames[w])s" }
        if let d = e.day { s += " on day \(d) of the month" }
        return s
    }
}

/// Friendly schedule choices that expand into `StartCalendarInterval` entries.
enum SchedulePreset: String, CaseIterable, Identifiable {
    case hourly = "Every hour", daily = "Every day", weekdays = "Every weekday", weekly = "Every week", monthly = "Every month"
    var id: String { rawValue }

    func entries(hour: Int, minute: Int, weekday: Int, day: Int) -> [CalendarEntry] {
        switch self {
        case .hourly: return [CalendarEntry(minute: minute)]
        case .daily: return [CalendarEntry(minute: minute, hour: hour)]
        case .weekdays: return (1...5).map { CalendarEntry(minute: minute, hour: hour, weekday: $0) }
        case .weekly: return [CalendarEntry(minute: minute, hour: hour, weekday: weekday)]
        case .monthly: return [CalendarEntry(minute: minute, hour: hour, day: day)]
        }
    }
}

/// Starting points offered by the New Job picker.
enum JobTemplate: String, CaseIterable, Identifiable {
    case schedule = "Run script on a schedule"
    case login = "Run at login"
    case keepApp = "Keep an app running"
    case watch = "Run when a folder changes"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .schedule: return "calendar.badge.clock"
        case .login: return "person.crop.circle.badge.checkmark"
        case .keepApp: return "arrow.clockwise.circle"
        case .watch: return "folder.badge.gearshape"
        }
    }

    var detail: String {
        switch self {
        case .schedule: return "Runs a shell script every weekday at 09:00."
        case .login: return "Opens an app or runs a command each time you log in."
        case .keepApp: return "Relaunches an app whenever it quits."
        case .watch: return "Runs a command when files in a folder change (WatchPaths)."
        }
    }

    func make(prefix: String) -> LaunchJob {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let base = prefix.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        var job = LaunchJob()
        switch self {
        case .schedule:
            job.label = "\(base).script"
            job.program = "/bin/sh"
            job.arguments = ["\(home)/bin/myscript.sh"]
            job.calendar = SchedulePreset.weekdays.entries(hour: 9, minute: 0, weekday: 1, day: 1)
        case .login:
            job.label = "\(base).login"
            job.program = "/usr/bin/open"
            job.arguments = ["-a", "Notes"]
            job.runAtLoad = true
        case .keepApp:
            job.label = "\(base).keepalive"
            job.program = "/usr/bin/open"
            job.arguments = ["-W", "-a", "TextEdit"]
            job.runAtLoad = true
            job.keepAlive = true
        case .watch:
            job.label = "\(base).watch"
            job.program = "/bin/sh"
            job.arguments = ["-c", "echo \"Folder changed: $(date)\""]
            job.watchPaths = ["\(home)/Downloads"]
        }
        job.standardOutPath = "\(home)/Library/Logs/\(job.label).log"
        job.standardErrorPath = job.standardOutPath
        return job
    }
}
