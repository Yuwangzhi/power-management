import Foundation

@main
struct PowerCoreTests {
    static func main() {
        let custom = """
        Battery Power:
         sleep                1
         displaysleep         5
         disksleep            10
         tcpkeepalive         1
        AC Power:
         sleep                1
         displaysleep         10
         disksleep            10
        """
        let batt = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t100%; charged; 0:00 remaining present: true"
        func state(_ disabled: Int = 0, _ settings: String = custom,
                   installed: Bool = false, loaded: Bool = false,
                   daemon: String = "", readable: Bool = true,
                   screenSaver: Int? = 0, screenSaverGuard: Bool = true) -> PowerSnapshot {
            PowerSnapshot.parse(system: "System-wide power settings:\n SleepDisabled\t\(disabled)\n", custom: settings,
                                batt: batt, daemon: daemon, installed: installed, loaded: loaded, readable: readable,
                                screenSaverIdleSeconds: screenSaver, screenSaverGuardInstalled: screenSaverGuard)
        }
        let normal = state()
        assert(normal.mode == .normal)
        assert(normal.ac["displaysleep"] == 10 && normal.battery["displaysleep"] == 5)
        assert(normal.source == "电源适配器" && normal.batteryPercent == 100 && normal.batteryState == "已充满")
        let awake = custom.replacingOccurrences(of: "sleep                1", with: "sleep                0")
            .replacingOccurrences(of: "displaysleep         5", with: "displaysleep         0")
            .replacingOccurrences(of: "displaysleep         10", with: "displaysleep         0")
            .replacingOccurrences(of: "disksleep            10", with: "disksleep            0")
        assert(state(1, awake, installed: true, loaded: true, daemon: "last exit code = 0").mode == .keepAwake)
        assert(state(1, awake, installed: true).mode == .partial)
        assert(state(1, awake, installed: true, loaded: true, daemon: "last exit code = 1").mode == .partial)
        assert(state(1, custom, installed: true, loaded: true).mode == .partial)
        assert(state(1, awake, installed: true, loaded: true, screenSaver: 1200).mode == .partial)
        assert(state(1, awake, installed: true, loaded: true, screenSaver: nil).mode == .partial)
        assert(state(1, awake, installed: true, loaded: true, screenSaverGuard: false).mode == .partial)
        assert(state(screenSaver: 1200, screenSaverGuard: false).mode == .normal)
        assert(state(installed: true).mode == .partial)
        assert(state(readable: false).mode == .unavailable)
        assert(state(0, "").mode == .unavailable)
        let battery = PowerSnapshot.parse(system: "SleepDisabled 0", custom: custom,
                                          batt: "Now drawing from 'Battery Power'\n 42%; discharging; 1:20 remaining",
                                          daemon: "", installed: false, loaded: false)
        assert(battery.source == "电池供电" && battery.batteryPercent == 42 && battery.batteryState == "正在使用电池")
        assert(PowerSnapshot.minutes(nil) == "—" && PowerSnapshot.minutes(0) == "永不")
        assert(ScreenSaverSettings.description(0) == "永不")
        assert(ScreenSaverSettings.description(1200) == "20 分钟后")
        assert(ScreenSaverSettings.description(nil) == "无法读取")
        let path = "/tmp/Power 中文 'quoted' \"folder\"/$(touch should-not-exist)`whoami`"
        let quoted = Shell.run("/bin/zsh", ["-c", "/usr/bin/printf '%s' " + Shell.quote(path)])
        assert(quoted.status == 0 && quoted.output == path)
        let literal = Shell.run("/usr/bin/osascript", ["-e", "return " + Shell.appleScriptLiteral(path)])
        assert(literal.status == 0 && literal.output.trimmingCharacters(in: .newlines) == path)
        print("PowerCore: normal/awake/partial/unavailable, AC/battery parsing, and shell/AppleScript quoting passed.")
    }
}
