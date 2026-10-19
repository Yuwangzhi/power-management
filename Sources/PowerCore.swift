import Foundation
import CoreFoundation

struct CommandResult {
    let status: Int32
    let output: String
}

enum Shell {
    static func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CommandResult(status: process.terminationStatus,
                                 output: String(decoding: data, as: UTF8.self))
        } catch {
            return CommandResult(status: -1, output: error.localizedDescription)
        }
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}

enum PowerMode: String, Codable {
    case normal, keepAwake, partial, unavailable

    var title: String {
        switch self {
        case .normal: return "正常睡眠"
        case .keepAwake: return "防睡眠已开启"
        case .partial: return "防睡眠需要修复"
        case .unavailable: return "暂时无法读取状态"
        }
    }

    var detail: String {
        switch self {
        case .normal: return "Mac 按当前电源策略睡眠。开启防睡眠会同时关闭自动屏保；恢复正常睡眠会将屏保设为 20 分钟。"
        case .keepAwake: return "已禁用自动睡眠和自动屏保，关闭窗口后也会持续生效。网络连接仍取决于实际网络。"
        case .partial: return "电源、自动屏保或后台服务不完全一致。可以修复并开启防睡眠，或恢复正常睡眠。"
        case .unavailable: return "读取系统电源设置失败，请刷新状态或查看诊断信息。"
        }
    }

    var symbol: String {
        switch self {
        case .normal: return "moon.zzz.fill"
        case .keepAwake: return "bolt.shield.fill"
        case .partial: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle.fill"
        }
    }
}

enum ScreenSaverSettings {
    static let defaultSeconds = 20 * 60
    static let guardPath = "/usr/local/sbin/screensaver-settings.sh"

    static func captureIdleSeconds() -> Int? {
        let domain = "com.apple.screensaver" as CFString
        for host in [kCFPreferencesCurrentHost, kCFPreferencesAnyHost] {
            guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, host) else { return nil }
            if let value = CFPreferencesCopyValue("idleTime" as CFString, domain, kCFPreferencesCurrentUser, host) {
                guard let number = value as? NSNumber, number.intValue >= 0 else { return nil }
                return number.intValue
            }
        }
        return defaultSeconds
    }

    static var guardInstalled: Bool {
        guard FileManager.default.isExecutableFile(atPath: guardPath),
              let script = try? String(contentsOfFile: "/usr/local/sbin/codex-power-keepawake.sh", encoding: .utf8) else {
            return false
        }
        return script.contains("/screensaver-settings.sh\" 0")
    }

    static func description(_ seconds: Int?) -> String {
        guard let seconds = seconds else { return "无法读取" }
        if seconds == 0 { return "永不" }
        return seconds.isMultiple(of: 60) ? "\(seconds / 60) 分钟后" : "\(seconds) 秒后"
    }
}

struct PowerSnapshot: Codable {
    static let label = "com.yuwangzhi.codex-power-keepawake"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"

    let capturedAt: Date
    let mode: PowerMode
    let sleepDisabled: Int?
    let daemonInstalled: Bool
    let daemonLoaded: Bool
    let daemonLastExitCode: Int?
    let screenSaverIdleSeconds: Int?
    let screenSaverGuardInstalled: Bool
    let source: String
    let batteryPercent: Int?
    let batteryState: String
    let ac: [String: Int]
    let battery: [String: Int]
    let raw: String

    static func settings(_ text: String) -> (ac: [String: Int], battery: [String: Int]) {
        var ac: [String: Int] = [:]
        var battery: [String: Int] = [:]
        var section = ""
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "AC Power:" { section = "ac"; continue }
            if trimmed == "Battery Power:" { section = "battery"; continue }
            if trimmed.hasSuffix(":") { section = ""; continue }
            let fields = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 2, let value = Int(fields[1]) else { continue }
            if section == "ac" { ac[String(fields[0])] = value }
            if section == "battery" { battery[String(fields[0])] = value }
        }
        return (ac, battery)
    }

    static func parse(system: String, custom: String, batt: String,
                      daemon: String, installed: Bool, loaded: Bool,
                      readable: Bool = true, screenSaverIdleSeconds: Int? = nil,
                      screenSaverGuardInstalled: Bool = false) -> PowerSnapshot {
        func integer(after key: String, in text: String) -> Int? {
            for line in text.components(separatedBy: .newlines) {
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                if fields.first == Substring(key), fields.count > 1 { return Int(fields[1]) }
            }
            return nil
        }
        let sleepDisabled = integer(after: "SleepDisabled", in: system)
        let values = settings(custom)
        var daemonExit: Int?
        if let line = daemon.components(separatedBy: .newlines).first(where: { $0.contains("last exit code =") }) {
            daemonExit = Int(line.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        let allAwake = [values.ac, values.battery].allSatisfy { settings in
            ["sleep", "displaysleep", "disksleep"].allSatisfy { settings[$0] == 0 }
        }
        let hasSettings = sleepDisabled != nil && values.ac["sleep"] != nil && values.battery["sleep"] != nil
        let mode: PowerMode
        if !readable || !hasSettings { mode = .unavailable }
        else if sleepDisabled == 1 && loaded && allAwake && (daemonExit ?? 0) == 0 &&
                    screenSaverIdleSeconds == 0 && screenSaverGuardInstalled { mode = .keepAwake }
        else if sleepDisabled == 1 || installed || loaded { mode = .partial }
        else { mode = .normal }

        let source = batt.contains("'AC Power'") ? "电源适配器" :
            (batt.contains("'Battery Power'") ? "电池供电" : "未知电源")
        let percentage: Int?
        if let range = batt.range(of: #"\d+(?=%)"#, options: .regularExpression) {
            percentage = Int(batt[range])
        } else { percentage = nil }
        let batteryState: String
        if batt.contains("discharging;") { batteryState = "正在使用电池" }
        else if batt.contains("not charging;") { batteryState = "未在充电" }
        else if batt.contains("charged;") { batteryState = "已充满" }
        else if batt.contains("charging;") { batteryState = "正在充电" }
        else { batteryState = "电池状态未知" }

        return PowerSnapshot(capturedAt: Date(), mode: mode, sleepDisabled: sleepDisabled,
                             daemonInstalled: installed, daemonLoaded: loaded,
                             daemonLastExitCode: daemonExit,
                             screenSaverIdleSeconds: screenSaverIdleSeconds,
                             screenSaverGuardInstalled: screenSaverGuardInstalled,
                             source: source,
                             batteryPercent: percentage, batteryState: batteryState,
                             ac: values.ac, battery: values.battery,
                             raw: "pmset -g\n\(system)\npmset -g custom\n\(custom)\npmset -g batt\n\(batt)\nlaunchctl\n\(daemon)\nscreen saver\nidleTime = \(screenSaverIdleSeconds.map(String.init) ?? "unavailable")\nbackground screen saver control installed = \(screenSaverGuardInstalled)")
    }

    static func capture() -> PowerSnapshot {
        let system = Shell.run("/usr/bin/pmset", ["-g"])
        let custom = Shell.run("/usr/bin/pmset", ["-g", "custom"])
        let batt = Shell.run("/usr/bin/pmset", ["-g", "batt"])
        let daemon = Shell.run("/bin/launchctl", ["print", "system/\(label)"])
        return parse(system: system.output, custom: custom.output, batt: batt.output,
                     daemon: daemon.output, installed: FileManager.default.fileExists(atPath: plistPath),
                     loaded: daemon.status == 0,
                     readable: system.status == 0 && custom.status == 0 && batt.status == 0,
                     screenSaverIdleSeconds: ScreenSaverSettings.captureIdleSeconds(),
                     screenSaverGuardInstalled: ScreenSaverSettings.guardInstalled)
    }

    static func minutes(_ value: Int?) -> String {
        guard let value = value else { return "—" }
        return value == 0 ? "永不" : "\(value) 分钟"
    }
}
