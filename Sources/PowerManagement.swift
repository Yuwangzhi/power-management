import AppKit
import SwiftUI

@MainActor
final class PowerModel: ObservableObject {
    @Published var snapshot: PowerSnapshot?
    @Published var refreshing = false
    @Published var changing = false
    @Published var notice: String?
    @Published var errorMessage: String?
    @Published var showDiagnostics = false
    var onUpdate: (() -> Void)?
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !refreshing, !changing else { return }
        refreshing = true
        Task {
            let result = await Task.detached { PowerSnapshot.capture() }.value
            snapshot = result
            refreshing = false
            onUpdate?()
        }
    }

    func changeMode(enable: Bool) {
        guard !changing, !refreshing else { return }
        changing = true
        notice = nil
        Task {
            let outcome = await Task.detached { Self.authorize(enable: enable) }.value
            changing = false
            if outcome.status == 0 {
                let result = await Task.detached { PowerSnapshot.capture() }.value
                snapshot = result
                let succeeded = enable ? result.mode == .keepAwake :
                    result.mode == .normal && result.screenSaverIdleSeconds == ScreenSaverSettings.defaultSeconds
                if succeeded {
                    if enable {
                        notice = "防睡眠已开启，自动屏保已设为永不；关闭窗口后也会持续生效。"
                    } else {
                        notice = outcome.output.contains("Restored legacy normal sleep defaults.")
                            ? "已关闭旧版防睡眠，恢复正常睡眠默认值；自动屏保已设为 20 分钟。"
                            : "已关闭防睡眠，恢复开启前的电源设置；自动屏保已设为 20 分钟。"
                    }
                } else {
                    errorMessage = "操作已执行，但系统状态未达到预期。请查看诊断信息。\n\n\(outcome.output)"
                }
                onUpdate?()
            } else if outcome.output.contains("(-128)") || outcome.output.contains("User canceled") {
                notice = "已取消授权，未执行切换操作。"
                refresh()
            } else {
                errorMessage = "切换未完成。\n\n\(outcome.output.trimmingCharacters(in: .whitespacesAndNewlines))"
                refresh()
            }
        }
    }

    nonisolated static func authorize(enable: Bool) -> CommandResult {
        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("Scripts") else {
            return CommandResult(status: -1, output: "找不到 App 内置的电源管理脚本。")
        }
        let script = resources.appendingPathComponent(enable ? "install.sh" : "restore-default-sleep.sh")
        let command = "/bin/zsh " + Shell.quote(script.path)
        let appleScript = "do shell script " + Shell.appleScriptLiteral(command) + " with administrator privileges"
        return Shell.run("/usr/bin/osascript", ["-e", appleScript])
    }

    func copyDiagnostics() {
        guard let snapshot = snapshot else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Power Management \(version)\n\(snapshot.capturedAt)\n\n\(snapshot.raw)", forType: .string)
        notice = "诊断信息已复制。"
    }
}

struct Dashboard: View {
    @ObservedObject var model: PowerModel
    private let accent = Color(red: 0.04, green: 0.53, blue: 0.61)
    private var mode: PowerMode { model.snapshot?.mode ?? .unavailable }
    private var statusColor: Color {
        mode == .keepAwake ? accent : (mode == .partial || mode == .unavailable ? .orange : .secondary)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                modeCard
                HStack(spacing: 14) {
                    metric("当前电源", value: model.snapshot?.source ?? "正在读取", icon: "powerplug.fill",
                           detail: model.snapshot?.source == "电池供电" ? "使用电池时注意剩余电量" : "已连接外部电源")
                    metric("电池电量", value: model.snapshot?.batteryPercent.map { "\($0)%" } ?? "—",
                           icon: "battery.100percent", detail: model.snapshot?.batteryState ?? "正在读取")
                    metric("后台守护", value: model.snapshot?.daemonLoaded == true ? "已加载" : "未启用",
                           icon: "arrow.triangle.2.circlepath", detail: model.snapshot?.daemonLoaded == true ? "每 15 秒自动应用" : "开启防睡眠时自动安装")
                }
                settingsCard
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle").padding(.top, 2)
                    Text("防睡眠同时作用于插电与电池模式，并关闭当前登录用户的自动屏保；恢复正常睡眠时屏保设为 20 分钟。合盖时请保持散热。切换需管理员授权。")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                if let notice = model.notice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.system(size: 12)).foregroundStyle(accent)
                        .accessibilityIdentifier("operationNotice")
                }
                DisclosureGroup("诊断信息", isExpanded: $model.showDiagnostics) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("系统实时输出").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("复制诊断信息") { model.copyDiagnostics() }
                                .accessibilityIdentifier("copyDiagnostics")
                        }
                        Text(model.snapshot?.raw ?? "正在读取…")
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.top, 12)
                }
                .font(.system(size: 12))
                footer
            }.padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 740, minHeight: 660)
        .tint(accent)
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text("Power Management").font(.system(size: 25, weight: .semibold))
                Text("让任务继续，让电源状态一目了然").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.refresh() } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.refreshing || model.changing)
            .accessibilityIdentifier("refreshStatus")
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: mode.symbol).font(.system(size: 28)).foregroundStyle(statusColor)
                    .frame(width: 42, height: 42)
                    .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.snapshot == nil ? "正在读取状态…" : mode.title)
                        .font(.system(size: 22, weight: .semibold))
                        .accessibilityIdentifier("currentPowerMode")
                    Text(mode.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                Button { model.changeMode(enable: true) } label: {
                    Label(mode == .partial ? "修复并开启防睡眠" : "开启防睡眠", systemImage: "bolt.fill")
                        .frame(minWidth: 132)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.snapshot == nil || mode == .keepAwake || mode == .unavailable || model.changing || model.refreshing)
                .accessibilityIdentifier("enableKeepAwake")
                Button { model.changeMode(enable: false) } label: {
                    Label("恢复正常睡眠", systemImage: "moon.fill").frame(minWidth: 132)
                }
                .controlSize(.large)
                .disabled(model.snapshot == nil || (mode == .normal && model.snapshot?.screenSaverIdleSeconds == ScreenSaverSettings.defaultSeconds) || mode == .unavailable || model.changing || model.refreshing)
                .accessibilityIdentifier("restoreSleep")
                if model.changing {
                    ProgressView().controlSize(.small)
                    Text("等待系统授权或应用设置…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(statusColor.opacity(0.16)))
    }

    private func metric(_ title: String, value: String, icon: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .semibold)).lineLimit(1)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("当前睡眠策略").font(.system(size: 13, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 10) {
                GridRow {
                    Text("供电模式")
                    Text("系统睡眠")
                    Text("显示器睡眠")
                    Text("磁盘睡眠")
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                Divider().gridCellColumns(4)
                policyRow("插电", values: model.snapshot?.ac)
                policyRow("电池", values: model.snapshot?.battery)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            HStack(spacing: 12) {
                Label("自动屏保", systemImage: "display")
                Spacer()
                Text(ScreenSaverSettings.description(model.snapshot?.screenSaverIdleSeconds))
                    .fontWeight(.medium)
                    .accessibilityIdentifier("screenSaverIdleTime")
            }.font(.system(size: 12))
            Label("随防睡眠切换：开启时永不，关闭时 20 分钟后", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private func policyRow(_ title: String, values: [String: Int]?) -> some View {
        GridRow {
            Text(title).fontWeight(.medium)
            Text(PowerSnapshot.minutes(values?["sleep"]))
            Text(PowerSnapshot.minutes(values?["displaysleep"]))
            Text(PowerSnapshot.minutes(values?["disksleep"]))
        }.font(.system(size: 12))
    }

    private var footer: some View {
        HStack {
            if let time = model.snapshot?.capturedAt {
                Text("更新于 \(time.formatted(date: .omitted, time: .standard)) · 每 15 秒刷新")
            }
            Spacer()
            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
        }.font(.system(size: 10)).foregroundStyle(.tertiary)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private let model = PowerModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 790, height: 750),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Power Management"
        window.minSize = NSSize(width: 740, height: 700)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Dashboard(model: model))
        window.center()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Power Management")
        let menu = NSMenu()
        menu.addItem(withTitle: "显示 Power Management", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(withTitle: "刷新状态", action: #selector(refreshStatus), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Power Management", action: #selector(quit), keyEquivalent: "")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        model.onUpdate = { [weak self] in
            guard let self = self else { return }
            self.statusItem.button?.toolTip = "Power Management · \(self.model.snapshot?.mode.title ?? "正在读取")"
        }
        model.start()
        showWindow()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshStatus),
                                                         name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func makeMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Power Management")
        appMenu.addItem(withTitle: "关于 Power Management", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Power Management", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Power Management", action: #selector(quit), keyEquivalent: "q").target = self
        appMenu.items.first?.target = self
        appItem.submenu = appMenu
        main.addItem(appItem)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        main.addItem(edit)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "显示 Power Management", action: #selector(showWindow), keyEquivalent: "0").target = self
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.refresh()
    }
    @objc func refreshStatus() { model.refresh() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "电源状态与防睡眠管理\n由 Yuwangzhi 维护"),
            .applicationName: "Power Management"
        ])
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct PowerManagementMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let state = PowerSnapshot.capture()
            if let data = try? encoder.encode(state) { print(String(decoding: data, as: UTF8.self)) }
            exit(state.mode == .unavailable ? 1 : 0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
