import SwiftUI
import AppKit
import IOKit
import IOKit.ps
import Combine
import CoreGraphics

// MARK: - 覆盖层窗口（标记类型，便于与面板区分层级）
final class OverlayWindow: NSWindow {}

// MARK: - 屏幕亮度（覆盖层软件调光，物理可见，不依赖显卡驱动）
final class OverlayDimmer {
    static let shared = OverlayDimmer()
    private var dimWin: NSWindow?
    private var warmWin: NSWindow?
    private let dimLevel = 300
    private let warmLevel = 301
    private func frame() -> NSRect { NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080) }
    private func make(_ lvl: Int) -> NSWindow {
        let w = OverlayWindow(contentRect: frame(), styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.level = NSWindow.Level(rawValue: lvl)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return w
    }
    func apply(level L: Float, warm W: Float) {
        let aDim = CGFloat(max(0, 1.0 - L))
        if aDim < 0.01 { dimWin?.orderOut(nil) }
        else {
            if dimWin == nil { dimWin = make(dimLevel) }
            dimWin?.backgroundColor = NSColor.black.withAlphaComponent(aDim)
            dimWin?.setFrame(frame(), display: true)
            dimWin?.orderFrontRegardless()
        }
        let aWarm = CGFloat(W) * 0.5 * CGFloat(max(0.2, L))
        if aWarm < 0.01 { warmWin?.orderOut(nil) }
        else {
            if warmWin == nil { warmWin = make(warmLevel) }
            warmWin?.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.15, alpha: aWarm)
            warmWin?.setFrame(frame(), display: true)
            warmWin?.orderFrontRegardless()
        }
    }
    func reset() { dimWin?.orderOut(nil); warmWin?.orderOut(nil) }
}

// MARK: - 全局热键（Fn 键在 EC/ATKD 层被消费，故额外支持可达组合键）
extension Notification.Name {
    static let asusBrightUp = Notification.Name("asusBrightUp")
    static let asusBrightDown = Notification.Name("asusBrightDown")
    static let asusFanUp = Notification.Name("asusFanUp")
    static let asusFanDown = Notification.Name("asusFanDown")
}

func hotLog(_ s: String) {
    let line = "\(s) \(Date())\n"
    let p = "/tmp/asus_keys.log"
    if let h = FileHandle(forWritingAtPath: p) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    } else { try? line.write(toFile: p, atomically: true, encoding: .utf8) }
}

func hotkeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type.rawValue == 14 {
        if let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 {
            let kc = Int(ns.data1) >> 16
            if kc == 3 { DispatchQueue.main.async { NotificationCenter.default.post(name: .asusBrightUp, object: nil) }; hotLog("SYSDEF up (kc3)") }
            else if kc == 2 { DispatchQueue.main.async { NotificationCenter.default.post(name: .asusBrightDown, object: nil) }; hotLog("SYSDEF down (kc2)") }
            else { hotLog("SYSDEF kc=\(kc)") }
        }
    } else if type == .keyDown {
        let f = event.flags
        let ctrl = f.contains(.maskControl)
        let opt = f.contains(.maskAlternate)
        let kc = event.getIntegerValueField(.keyboardEventKeycode)
        if ctrl && opt {
            if kc == 126 { DispatchQueue.main.async { NotificationCenter.default.post(name: .asusBrightUp, object: nil) }; hotLog("KEY ctrl+opt+up -> bright+") }
            else if kc == 125 { DispatchQueue.main.async { NotificationCenter.default.post(name: .asusBrightDown, object: nil) }; hotLog("KEY ctrl+opt+down -> bright-") }
            else if kc == 124 { DispatchQueue.main.async { NotificationCenter.default.post(name: .asusFanUp, object: nil) }; hotLog("KEY ctrl+opt+right -> fan+") }
            else if kc == 123 { DispatchQueue.main.async { NotificationCenter.default.post(name: .asusFanDown, object: nil) }; hotLog("KEY ctrl+opt+left -> fan-") }
        } else {
            hotLog("KEYDOWN code=\(kc)")
        }
    }
    return Unmanaged.passUnretained(event)
}

final class HotkeyTap {
    static let shared = HotkeyTap()
    private var tap: CFMachPort?
    func start() {
        let mask = (1 << 14) | (1 << CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: CGEventMask(mask), callback: hotkeyCallback, userInfo: nil) else {
            hotLog("HOTKEY_TAP_FAIL"); return
        }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        hotLog("HOTKEY_TAP_OK")
    }
}

// MARK: - ASUS WMI 用户客户端
final class AsusWMI {
    private var conn: io_connect_t = 0
    private var opened = false
    func open() {
        guard !opened else { return }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AsusWMIControl"))
        guard svc != 0 else { return }
        defer { IOObjectRelease(svc) }
        var c: io_connect_t = 0
        if IOServiceOpen(svc, mach_task_self_, 0, &c) == KERN_SUCCESS { conn = c; opened = true }
    }
    // sGetInfo(sel0, 92B): off8=kbdLevel, off12=thermalPolicy(0静音/1均衡/2性能)
    func info() -> (mode: Int, kbd: Int)? {
        open(); guard opened else { return nil }
        var out = [UInt8](repeating: 0, count: 92); var sz = 92
        let kr = IOConnectCallStructMethod(conn, 0, nil, 0, &out, &sz)
        if kr != 0 { return nil }
        return out.withUnsafeBytes { p in
            (Int(p.load(fromByteOffset: 12, as: UInt32.self)), Int(p.load(fromByteOffset: 8, as: UInt32.self)))
        }
    }
    @discardableResult private func set(_ sel: UInt32, _ v: Int) -> Bool {
        open(); guard opened else { return false }
        var val = [UInt64(UInt32(max(0, v)))]
        return IOConnectCallScalarMethod(conn, sel, &val, 1, nil, nil) == KERN_SUCCESS
    }
    func setThermal(_ v: Int) -> Bool { set(4, v) }   // 0..2
    func setKbd(_ v: Int) -> Bool { set(1, v) }        // 0..3
    func setCharge(_ v: Int) -> Bool { set(5, v) }     // 20..100
}

// MARK: - 系统监控
final class Monitor: ObservableObject {
    @Published var cpu: Double = 0
    @Published var memUsedGB: Double = 0
    @Published var memTotalGB: Double = 0
    @Published var battery: Int = 0
    @Published var charging = false
    private var timer: Timer?
    private var last: (u: Double, s: Double, i: Double)? = nil
    init() { sample(); timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() } }
    func sample() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var cl = host_cpu_load_info_data_t()
        _ = withUnsafeMutablePointer(to: &cl) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size) } }
        let u = Double(cl.cpu_ticks.0), s = Double(cl.cpu_ticks.1), i = Double(cl.cpu_ticks.2)
        if let l = last { let du = u - l.u, ds = s - l.s, di = i - l.i, t = du + ds + di; if t > 0 { cpu = (du + ds) / t * 100 } }
        last = (u, s, i)
        var vm = vm_statistics64()
        var cnt = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &vm) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(cnt)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &cnt) } }
        let page = Double(vm_kernel_page_size)
        let used = (Double(vm.active_count) + Double(vm.inactive_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
        memUsedGB = used / 1_073_741_824
        memTotalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        if let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                if let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any] {
                    if let cap = d[kIOPSCurrentCapacityKey] as? Int { battery = cap }
                    charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
                }
            }
        }
    }
}

// MARK: - UI
struct Card<Content: View>: View {
    let title: String; let icon: String; @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) { Image(systemName: icon).foregroundStyle(.blue); Text(title).font(.headline) }
            content
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct ContentView: View {
    @StateObject var mon = Monitor()
    let wmi = AsusWMI()
    @State private var level: Double = 1.0
    @State private var warm: Double = 0.0
    @State private var mode: Int = 1
    @State private var kbd: Double = 3
    @State private var charge: Int = 100
    @State private var toast: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 标题
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ASUS 控制台").font(.title2).bold()
                        Text("Zenbook UX3402VA · i9-13900H").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !toast.isEmpty { Text(toast).font(.caption).foregroundStyle(.green) }
                }

                // 亮度
                Card(title: "屏幕亮度 / 护眼", icon: "sun.max.fill") {
                    HStack { Image(systemName: "sun.min").foregroundStyle(.secondary); Slider(value: $level, in: 0.2...1.0).onChange(of: level) { _, v in applyDim() }; Image(systemName: "sun.max").foregroundStyle(.secondary) }
                    Text("亮度 \(Int(level*100))%").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("白天") { level = 1.0; warm = 0.0; applyDim() }
                        Button("柔和") { level = 0.82; warm = 0.12; applyDim() }
                        Button("夜间护眼") { level = 0.6; warm = 0.65; applyDim() }
                    }.buttonStyle(.bordered)
                    Text("软件调光（覆盖层），物理可见、不依赖显卡驱动、免重启；关闭本窗口即恢复。快捷键：⌃⌥↑ 加亮 / ⌃⌥↓ 减暗，⌃⌥←/→ 切风扇档").font(.caption2).foregroundStyle(.secondary)
                }

                // 性能模式
                Card(title: "性能模式（风扇曲线随之切换）", icon: "speedometer") {
                    HStack(spacing: 8) {
                        modeBtn("静音", 0, "leaf"); modeBtn("均衡", 1, "equal"); modeBtn("性能", 2, "bolt.fill")
                    }
                }

                // 键盘背光
                Card(title: "键盘背光", icon: "keyboard") {
                    HStack(spacing: 8) { Image(systemName: "keyboard").foregroundStyle(.secondary); Slider(value: $kbd, in: 0...3, step: 1).onChange(of: kbd) { _, v in _ = wmi.setKbd(Int(v)); flash("键盘 \(Int(v))") }; Text(["关", "低", "中", "高"][min(3, max(0, Int(kbd)))]).font(.callout).foregroundStyle(.secondary).frame(width: 30) }
                }

                // 充电上限
                Card(title: "充电上限（保护电池）", icon: "battery.100") {
                    Picker("", selection: $charge) {
                        Text("100%").tag(100); Text("80%").tag(80); Text("60%").tag(60)
                    }.pickerStyle(.segmented).onChange(of: charge) { _, v in _ = wmi.setCharge(v); flash("充电上限 \(v)%") }
                }

                // 风扇/灯效 -> MHelper
                Card(title: "风扇 / 灯效 / 更多", icon: "fanblades") {
                    HStack {
                        Button("打开 MHelper 控制面板") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/MHelper.app")) }
                        Spacer()
                    }
                    Text("风扇曲线、RGB 灯效、dGPU Eco 等在 MHelper（菜单栏）里调").font(.caption2).foregroundStyle(.secondary)
                }

                // 系统状态
                Card(title: "系统状态", icon: "gauge.with.dots.needle.bottom.50percent") {
                    row("CPU 占用", String(format: "%.0f%%", mon.cpu))
                    row("内存", String(format: "%.1f / %.0f GB", mon.memUsedGB, mon.memTotalGB))
                    row("电池", "\(mon.battery)%" + (mon.charging ? "（充电中）" : ""))
                    row("当前性能模式", ["静音", "均衡", "性能"][min(2, max(0, mode))])
                }

                Text("风扇转速 / 温度：本机型 EC 不经 WMI 提供，无法实时读取。\n图形加速：Intel 核显 0xa7a0 无 macOS 驱动（详见修复报告）。")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 4)
            }
            .padding(16)
        }
        .frame(width: 460, height: 850)
        .onAppear {
            if let i = wmi.info() { mode = i.mode; kbd = Double(i.kbd) }
            if FileManager.default.fileExists(atPath: "/tmp/asus_dimtest") { level = 0.6; warm = 0.65 }
            applyDim()
        }
        .onReceive(NotificationCenter.default.publisher(for: .asusBrightUp)) { _ in brightStep(+0.1) }
        .onReceive(NotificationCenter.default.publisher(for: .asusBrightDown)) { _ in brightStep(-0.1) }
        .onReceive(NotificationCenter.default.publisher(for: .asusFanUp)) { _ in fanCycle(+1) }
        .onReceive(NotificationCenter.default.publisher(for: .asusFanDown)) { _ in fanCycle(-1) }
    }

    func brightStep(_ d: Double) { level = min(1.0, max(0.2, level + d)); applyDim(); flash("亮度 \(Int(level*100))%") }
    func fanCycle(_ d: Int) { mode = min(2, max(0, mode + d)); _ = wmi.setThermal(mode); flash("模式 \(["静音","均衡","性能"][mode])") }

    func applyDim() { OverlayDimmer.shared.apply(level: Float(level), warm: Float(warm)) }
    func modeBtn(_ t: String, _ v: Int, _ icon: String) -> some View {
        Button { _ = wmi.setThermal(v); mode = v; flash("模式:\(t)") } label: {
            VStack(spacing: 4) { Image(systemName: icon).font(.title3); Text(t).font(.callout) }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(mode == v ? .blue : .gray)
    }
    func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).bold() }.font(.callout)
    }
    func flash(_ s: String) { toast = s; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { if toast == s { toast = "" } } }
}

// MARK: - App
class AppDelegate: NSObject, NSApplicationDelegate {
    private func setPanelLevel(_ lv: Int) {
        for w in NSApp.windows where !(w is OverlayWindow) { w.level = NSWindow.Level(rawValue: lv) }
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        HotkeyTap.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.setPanelLevel(302) }
    }
    func applicationDidBecomeActive(_ n: Notification) { setPanelLevel(302) }
    func applicationDidResignActive(_ n: Notification) { setPanelLevel(0) }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { OverlayDimmer.shared.reset() }
}

@main
struct AsusConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { WindowGroup { ContentView() }.windowResizability(.contentSize) }
}
