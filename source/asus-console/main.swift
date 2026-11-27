import SwiftUI
import AppKit
import IOKit
import IOKit.hid
import IOKit.ps
import Combine
import CoreGraphics
import QuartzCore

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

// MARK: - 日志
func appendLog(_ path: String, _ s: String) {
    let line = "\(s) \(Date())\n"
    if let h = FileHandle(forWritingAtPath: path) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
    } else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
}
func hotLog(_ s: String) { appendLog("/tmp/asus_keys.log", s) }
func hidLog(_ s: String) { appendLog("/tmp/asus_hid.log", s) }

// MARK: - 全局热键（Fn 键在 EC/ATKD 层被消费，故额外支持可达组合键）
extension Notification.Name {
    static let asusBrightUp = Notification.Name("asusBrightUp")
    static let asusBrightDown = Notification.Name("asusBrightDown")
    static let asusFanUp = Notification.Name("asusFanUp")
    static let asusFanDown = Notification.Name("asusFanDown")
    static let asusShowMain = Notification.Name("asusShowMain")
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
            else if kc == 124 { DispatchQueue.main.async { NotificationCenter.default.post(name: .asusFanUp, object: nil) }; hotLog("KEY ctrl+opt+right -> mode+") }
            else if kc == 123 { DispatchQueue.main.async { NotificationCenter.default.post(name: .asusFanDown, object: nil) }; hotLog("KEY ctrl+opt+left -> mode-") }
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

// MARK: - HID 消费者控制监听（捕获 MHelper 虚拟键盘发出的媒体/亮度键，作为 Fn 键的补充通道）
final class HIDConsumerTap {
    static let shared = HIDConsumerTap()
    private var mgr: IOHIDManager?
    func start() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: 0x0C,
            kIOHIDDeviceUsageKey as String: 0x01
        ]
        IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
        let ctx = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(m, { _, _, _, value in
            let el = IOHIDValueGetElement(value)
            let page = IOHIDElementGetUsagePage(el)
            let usage = IOHIDElementGetUsage(el)
            let v = IOHIDValueGetIntegerValue(value)
            hidLog("CONSUMER page=\(page) usage=\(usage) val=\(v)")
            guard v != 0 else { return }
            switch usage {
            case 0x6F: DispatchQueue.main.async { NotificationCenter.default.post(name: .asusBrightUp, object: nil) }
            case 0x70: DispatchQueue.main.async { NotificationCenter.default.post(name: .asusBrightDown, object: nil) }
            default: break
            }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let r = IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        hidLog("HID_CONSUMER_OPEN ret=\(r)")
        mgr = m
    }
}

// MARK: - ASUS WMI 用户客户端
final class AsusWMI {
    static let shared = AsusWMI()
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
    // off16=chargeLimit(20..100), off68=fnLock(0关/1开, 未设置时为 -1)
    func info() -> (mode: Int, kbd: Int, chargeLimit: Int, fnLock: Int)? {
        open(); guard opened else { return nil }
        var out = [UInt8](repeating: 0, count: 92); var sz = 92
        let kr = IOConnectCallStructMethod(conn, 0, nil, 0, &out, &sz)
        if kr != 0 { return nil }
        return out.withUnsafeBytes { p in
            let kbd = Int(p.load(fromByteOffset: 8, as: UInt32.self))
            let thermal = Int(p.load(fromByteOffset: 12, as: UInt32.self))
            let charge = Int(p.load(fromByteOffset: 16, as: UInt32.self))
            let fn = Int(Int32(bitPattern: p.load(fromByteOffset: 68, as: UInt32.self)))
            return (thermal, kbd, charge, fn)
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
    func setFnLock(_ v: Int) -> Bool { set(10, v) }    // 0关 / 1开（该机 feature bit 0x2000 已置位，支持）
}

// MARK: - 与 MHelper 偏好同步（避免 MHelper 定时回写旧策略把我们的设置顶回去）
enum MHelperPrefs {
    static let d = UserDefaults(suiteName: "org.franciumos.mhelper.app")
    static func sync(mode: Int? = nil, kbd: Int? = nil, charge: Int? = nil, fn: Int? = nil) {
        guard let d = d else { return }
        if let m = mode { d.set(m, forKey: "policy") }
        if let k = kbd { d.set(k, forKey: "kbdLevel") }
        if let c = charge { d.set(c, forKey: "chargeLimit") }
        if let f = fn { d.set(f, forKey: "fnLock") }
        d.synchronize()
    }
}

// MARK: - MHelper 接管（单控制源，避免两边抢设置）
enum MHelperGuard {
    static let bundleID = "org.franciumos.mhelper.app"
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    static func terminate() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
    }
}

// MARK: - 系统监控 + 设置状态（持久化 + 策略守护）
final class Monitor: ObservableObject {
    static let shared = Monitor()
    let wmi = AsusWMI.shared
    private let ud = UserDefaults.standard

    @Published var cpu: Double = 0
    @Published var memUsedGB: Double = 0
    @Published var memTotalGB: Double = 0
    @Published var battery: Int = 0
    @Published var charging = false

    @Published var mode: Int = 1
    @Published var kbd: Int = 3
    @Published var charge: Int = 100
    @Published var fnLock: Bool = false

    // 只读：驱动回报的实际值
    @Published var driverMode: Int = -1
    @Published var driverKbd: Int = -1
    @Published var mhelperRunning: Bool = false
    @Published var takeover: Bool = true { didSet { ud.set(takeover, forKey: "takeover") } }

    private var timer: Timer?
    private var last: (u: Double, s: Double, i: Double)? = nil

    init() {
        if let i = wmi.info() {
            driverMode = i.mode; driverKbd = i.kbd
            mode = (ud.object(forKey: "mode") as? Int) ?? i.mode
            kbd = (ud.object(forKey: "kbd") as? Int) ?? max(0, min(3, i.kbd))
            if let c = ud.object(forKey: "charge") as? Int { charge = c }
            else { charge = (i.chargeLimit >= 20 && i.chargeLimit <= 100) ? i.chargeLimit : 100 }
            fnLock = (ud.object(forKey: "fnLock") as? Bool) ?? (i.fnLock == 1)
            // 首次运行把读到的实际值固化下来，后续开机由本 App 独立恢复
            if ud.object(forKey: "mode") == nil { ud.set(mode, forKey: "mode") }
            if ud.object(forKey: "kbd") == nil { ud.set(kbd, forKey: "kbd") }
            if ud.object(forKey: "charge") == nil { ud.set(charge, forKey: "charge") }
            if ud.object(forKey: "fnLock") == nil, i.fnLock == 0 || i.fnLock == 1 { ud.set(fnLock, forKey: "fnLock") }
        }
        takeover = (ud.object(forKey: "takeover") as? Bool) ?? true
        // 启动即把持久化的策略同步到 MHelper，避免它回写旧值
        MHelperPrefs.sync(mode: mode, kbd: kbd, charge: charge, fn: fnLock ? 1 : 0)
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    }

    func setMode(_ v: Int) {
        let c = min(2, max(0, v))
        mode = c; ud.set(c, forKey: "mode")
        _ = wmi.setThermal(c); MHelperPrefs.sync(mode: c); driverMode = c
    }
    func setKbd(_ v: Int) {
        let c = min(3, max(0, v))
        kbd = c; ud.set(c, forKey: "kbd")
        _ = wmi.setKbd(c); MHelperPrefs.sync(kbd: c)
    }
    func setCharge(_ v: Int) {
        charge = v; ud.set(v, forKey: "charge")
        _ = wmi.setCharge(v); MHelperPrefs.sync(charge: v)
    }
    func setFnLock(_ on: Bool) {
        fnLock = on; ud.set(on, forKey: "fnLock")
        _ = wmi.setFnLock(on ? 1 : 0); MHelperPrefs.sync(fn: on ? 1 : 0)
    }

    /// 启动时把持久化的硬件设置重新落实（MHelper 停用后由本 App 独立负责）
    func applySavedOnLaunch() {
        if ud.object(forKey: "mode") != nil { _ = wmi.setThermal(mode); driverMode = mode }
        if ud.object(forKey: "kbd") != nil { _ = wmi.setKbd(kbd) }
        if ud.object(forKey: "charge") != nil { _ = wmi.setCharge(charge) }
        if ud.object(forKey: "fnLock") != nil { _ = wmi.setFnLock(fnLock ? 1 : 0) }
    }

    /// 若开启接管且 MHelper 在运行，则退出它，保证只有一个控制源
    func enforceTakeover() {
        mhelperRunning = MHelperGuard.isRunning
        if takeover && mhelperRunning { MHelperGuard.terminate() }
    }

    func sample() {
        enforceTakeover()
        // 策略守护：驱动实际值被别的程序（MHelper 定时回写）改掉时，重新落实用户的选择
        if let i = wmi.info() {
            driverMode = i.mode; driverKbd = i.kbd
            if i.mode != mode { _ = wmi.setThermal(mode); MHelperPrefs.sync(mode: mode); driverMode = mode }
        }
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

// MARK: - 主题
enum T {
    static let bg1 = Color(red: 0.043, green: 0.059, blue: 0.102)
    static let bg2 = Color(red: 0.072, green: 0.098, blue: 0.176)
    static let accent = Color(red: 0.235, green: 0.886, blue: 0.788)
    static let accent2 = Color(red: 0.329, green: 0.620, blue: 1.0)
    static let violet = Color(red: 0.560, green: 0.360, blue: 0.960)
    static let amber = Color(red: 1.0, green: 0.686, blue: 0.353)
    static let card = Color.white.opacity(0.055)
    static let stroke = Color.white.opacity(0.10)
    static let txt = Color.white.opacity(0.95)
    static let sub = Color.white.opacity(0.55)
    static let sub2 = Color.white.opacity(0.38)
    static let modeNames = ["静音", "均衡", "性能"]
    static let modeIcons = ["leaf.fill", "equal.circle.fill", "bolt.fill"]
    static let modeColors = [Color(red: 0.42, green: 0.80, blue: 0.62), T.accent2, T.amber]
    static let kbdNames = ["关", "低", "中", "高"]
}

// MARK: - 玻璃粒子（原生 CAEmitterLayer，Apple 合成层，零依赖）
// 参考开源粒子库 twostraws/Vortex（MIT）的思路，改写为轻量版：玻璃珠 + 微光尘埃
func makeGlassBead(_ d: CGFloat = 72) -> CGImage? {
    let s = Int(d)
    guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let c = CGFloat(s) / 2
    let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 0.50),
                  CGColor(red: 0.78, green: 0.90, blue: 1.0, alpha: 0.16),
                  CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: c, y: c), startRadius: 0,
                               endCenter: CGPoint(x: c, y: c), endRadius: c, options: [])
    }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
    ctx.fillEllipse(in: CGRect(x: c * 0.55, y: c * 1.16, width: c * 0.44, height: c * 0.30))
    return ctx.makeImage()
}

enum ParticleStyle { case background, foreground }

final class GlassParticleView: NSView {
    private let emitter = CAEmitterLayer()
    private let style: ParticleStyle
    var motionOn: Bool = true { didSet { emitter.speed = motionOn ? 1 : 0 } }

    init(frame: NSRect, style: ParticleStyle) {
        self.style = style
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func cell(_ img: CGImage?, birth: Float, life: Float, v: CGFloat, vr: CGFloat,
                      scale: CGFloat, sr: CGFloat, alphaSpeed: Float, color: CGColor) -> CAEmitterCell {
        let c = CAEmitterCell()
        c.contents = img
        c.birthRate = birth
        c.lifetime = life
        c.velocity = v
        c.velocityRange = vr
        c.emissionRange = .pi * 0.35
        c.emissionLongitude = -.pi / 2
        c.yAcceleration = 1.0
        c.scale = scale
        c.scaleRange = sr
        c.scaleSpeed = -0.0018
        c.alphaSpeed = alphaSpeed
        c.spin = 0.2
        c.spinRange = 0.3
        c.color = color
        return c
    }

    private func setup() {
        let cool = CGColor(red: 0.85, green: 0.93, blue: 1.0, alpha: 1.0)
        if style == .background {
            let bead = cell(makeGlassBead(), birth: 1.7, life: 42, v: 26, vr: 10,
                            scale: 0.30, sr: 0.18, alphaSpeed: -0.020, color: cool)
            bead.emissionRange = .pi * 0.28
            let mote = cell(makeGlassBead(48), birth: 4.2, life: 32, v: 30, vr: 12,
                            scale: 0.10, sr: 0.06, alphaSpeed: -0.028, color: cool)
            emitter.emitterCells = [bead, mote]
            emitter.emitterShape = .line
            emitter.emitterMode = .outline
            emitter.beginTime = CACurrentMediaTime() - 38
        } else {
            let mote = cell(makeGlassBead(40), birth: 5.5, life: 16, v: 6, vr: 8,
                            scale: 0.06, sr: 0.04, alphaSpeed: -0.050, color: cool)
            mote.emissionRange = .pi * 0.9
            emitter.emitterCells = [mote]
            emitter.emitterShape = .rectangle
            emitter.emitterMode = .volume
            emitter.beginTime = CACurrentMediaTime() - 10
        }
        emitter.renderMode = .unordered
        emitter.speed = motionOn ? 1 : 0
        layer?.addSublayer(emitter)
    }

    override func layout() {
        super.layout()
        emitter.frame = bounds
        if style == .background {
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY + 6)
            emitter.emitterSize = CGSize(width: bounds.width * 1.2, height: 0)
        } else {
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
            emitter.emitterSize = bounds.size
        }
    }
}

struct GlassParticleField: NSViewRepresentable {
    var motionOn: Bool = true
    var style: ParticleStyle = .background
    func makeNSView(context: Context) -> NSView {
        let v = GlassParticleView(frame: .zero, style: style)
        v.motionOn = motionOn
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? GlassParticleView)?.motionOn = motionOn
    }
}

// MARK: - 动画背景（macOS 风格：柔和渐变 + 缓慢光晕 + 玻璃粒子）
struct AnimatedBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [T.bg1, T.bg2, Color(red: 0.085, green: 0.055, blue: 0.150)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(T.accent.opacity(0.07)).frame(width: 460).blur(radius: 140)
                .offset(x: -140, y: -180)
            Circle().fill(T.violet.opacity(0.08)).frame(width: 400).blur(radius: 150)
                .offset(x: 150, y: 220)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 玻璃卡片
struct GlassCard<Content: View>: View {
    var title: String
    var icon: String
    var tint: Color = T.accent
    @ViewBuilder var content: Content
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.16)).frame(width: 30, height: 30)
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                }
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(T.txt)
                Spacer(minLength: 0)
            }
            content
        }
        .padding(16)
        .glassEffect(.regular.tint(tint.opacity(hover ? 0.16 : 0.05)), in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(hover ? tint.opacity(0.45) : T.stroke, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: .black.opacity(0.30), radius: 20, x: 0, y: 10)
        .scaleEffect(hover ? 1.008 : 1)
        .animation(.snappy(duration: 0.22), value: hover)
        .onHover { hover = $0 }
    }
}

// MARK: - 状态小胶囊
struct StatusPill: View {
    var icon: String
    var text: String
    var color: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 0.8))
    }
}

// MARK: - 模式磁贴
struct ModeTile: View {
    var title: String
    var icon: String
    var color: Color
    var selected: Bool
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 20, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .foregroundStyle(selected ? Color.black.opacity(0.82) : T.txt)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(selected ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.72)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(hover ? 0.10 : 0.05)))
            )
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(selected ? color.opacity(0.9) : T.stroke, lineWidth: 1))
            .shadow(color: selected ? color.opacity(0.45) : .clear, radius: selected ? 14 : 0, x: 0, y: 5)
            .scaleEffect(selected ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - 环形仪表
struct RingGauge: View {
    var value: Double        // 0...1
    var color: Color
    var center: String
    var label: String
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.001, min(1.0, value)))
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
            VStack(spacing: 1) {
                Text(center).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(T.txt)
                    .contentTransition(.numericText())
                Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(T.sub2)
            }
        }
        .frame(width: 88, height: 88)
    }
}

// MARK: - 主界面
struct ContentView: View {
    @ObservedObject private var mon = Monitor.shared
    @AppStorage("level") private var level: Double = 1.0
    @AppStorage("warm") private var warm: Double = 0.0
    @AppStorage("motionOn") private var motionOn = false
    @State private var toast = ""
    @State private var toastWork: DispatchWorkItem?
    @State private var lastBright = Date.distantPast

    var body: some View {
        ZStack {
            AnimatedBackground()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    brightnessCard
                    perfCard
                    kbdCard
                    fnCard
                    chargeCard
                    statusCard
                    mhelperCard
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 46)
                .padding(.bottom, 22)
            }
            if motionOn {
                GlassParticleField(motionOn: true, style: .foreground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }
            toastOverlay
        }
        .frame(minWidth: 430, minHeight: 520)
        .preferredColorScheme(.dark)
        .onAppear { applyDim() }
        .onReceive(NotificationCenter.default.publisher(for: .asusBrightUp)) { _ in brightStep(+0.07) }
        .onReceive(NotificationCenter.default.publisher(for: .asusBrightDown)) { _ in brightStep(-0.07) }
        .onReceive(NotificationCenter.default.publisher(for: .asusFanUp)) { _ in cycleMode(+1) }
        .onReceive(NotificationCenter.default.publisher(for: .asusFanDown)) { _ in cycleMode(-1) }
    }

    // 顶部
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [T.accent.opacity(0.35), T.accent2.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ASUS 控制台")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, T.accent], startPoint: .leading, endPoint: .trailing))
                Text("Zenbook UX3402VA · i9‑13900H")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(T.sub2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                StatusPill(icon: "cpu", text: "CPU \(Int(mon.cpu))%", color: T.accent)
                StatusPill(icon: mon.charging ? "bolt.fill" : "battery.75", text: "\(mon.battery)%", color: mon.charging ? T.amber : T.accent2)
            }
        }
    }

    // 亮度
    private var brightnessCard: some View {
        GlassCard(title: "屏幕亮度 / 护眼", icon: "sun.max.fill", tint: T.amber) {
            HStack(spacing: 12) {
                Image(systemName: "sun.min.fill").font(.system(size: 13)).foregroundStyle(T.sub)
                Slider(value: $level, in: 0.2...1.0)
                    .tint(T.amber)
                    .onChange(of: level) { _, _ in applyDim() }
                Image(systemName: "sun.max.fill").font(.system(size: 17)).foregroundStyle(T.amber)
            }
            HStack {
                Text("亮度").font(.system(size: 11)).foregroundStyle(T.sub2)
                Spacer()
                Text("\(Int(level * 100))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(T.amber)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 8) {
                preset("白天", 1.0, 0.0)
                preset("柔和", 0.82, 0.12)
                preset("夜间护眼", 0.6, 0.65)
            }
            Text("软件覆盖层调光，物理可见、免重启；关闭窗口即恢复。⌃⌥↑ / ↓ 调亮度。")
                .font(.system(size: 10)).foregroundStyle(T.sub2)
        }
    }

    private func preset(_ name: String, _ l: Double, _ w: Double) -> some View {
        let active = abs(level - l) < 0.02 && abs(warm - w) < 0.02
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { level = l; warm = w }
            applyDim(); flash(name)
        } label: {
            Text(name).font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 7)
                .foregroundStyle(active ? Color.black.opacity(0.82) : T.txt)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? AnyShapeStyle(LinearGradient(colors: [T.amber, T.amber.opacity(0.75)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.06))))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(active ? T.amber : T.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // 性能模式
    private var perfCard: some View {
        GlassCard(title: "性能模式", icon: "speedometer", tint: T.accent2) {
            HStack(spacing: 9) {
                ForEach(0..<3, id: \.self) { i in
                    ModeTile(title: T.modeNames[i], icon: T.modeIcons[i], color: T.modeColors[i], selected: mon.mode == i) {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { mon.setMode(i) }
                        flash("已切换：\(T.modeNames[i])")
                    }
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.72), value: mon.mode)
            Text("风扇曲线随模式切换（WMI sSetThermal 0/1/2）。⌃⌥← / → 快速切换。")
                .font(.system(size: 10)).foregroundStyle(T.sub2)
        }
    }

    // 键盘背光
    private var kbdCard: some View {
        GlassCard(title: "键盘背光", icon: "keyboard", tint: T.accent) {
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { mon.setKbd(i) }
                        flash("背光 \(T.kbdNames[i])")
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: i == 0 ? "keyboard" : "light.max")
                                .font(.system(size: 15, weight: .semibold))
                            Text(T.kbdNames[i]).font(.system(size: 11, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(mon.kbd == i ? Color.black.opacity(0.82) : T.txt)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(mon.kbd == i ? AnyShapeStyle(LinearGradient(colors: [T.accent, T.accent.opacity(0.7)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.05))))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(mon.kbd == i ? T.accent : T.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Fn Lock
    private var fnCard: some View {
        GlassCard(title: "Fn Lock（功能键锁定）", icon: "fn", tint: T.violet) {
            Toggle(isOn: Binding(get: { mon.fnLock }, set: { v in mon.setFnLock(v); flash(v ? "Fn Lock 开" : "Fn Lock 关") })) {
                Text(mon.fnLock ? "已开启：F1–F12 直接生效，媒体功能需配合 Fn"
                                : "已关闭：F 键输出媒体功能（音量 / 亮度等）")
                    .font(.system(size: 12)).foregroundStyle(mon.fnLock ? T.txt : T.sub)
            }
            .toggleStyle(.switch)
            .tint(T.violet)
        }
    }

    // 充电上限
    private var chargeCard: some View {
        GlassCard(title: "充电上限（保护电池）", icon: "battery.100", tint: T.accent) {
            HStack(spacing: 8) {
                ForEach([100, 80, 60], id: \.self) { p in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { mon.setCharge(p) }
                        flash("充电上限 \(p)%")
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(p)%").font(.system(size: 15, weight: .bold, design: .rounded))
                            Text(p == 100 ? "满充" : (p == 80 ? "日常" : "长寿")).font(.system(size: 9)).foregroundStyle(T.sub2)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(mon.charge == p ? Color.black.opacity(0.82) : T.txt)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(mon.charge == p ? AnyShapeStyle(LinearGradient(colors: [T.accent, T.accent.opacity(0.7)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.05))))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(mon.charge == p ? T.accent : T.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // 系统状态
    private var statusCard: some View {
        GlassCard(title: "系统状态", icon: "gauge.with.dots.needle.50percent", tint: T.accent2) {
            HStack(spacing: 0) {
                RingGauge(value: mon.cpu / 100, color: T.accent, center: "\(Int(mon.cpu))%", label: "CPU")
                    .frame(maxWidth: .infinity)
                RingGauge(value: mon.memTotalGB > 0 ? mon.memUsedGB / mon.memTotalGB : 0,
                          color: T.accent2, center: String(format: "%.0f", mon.memUsedGB), label: "内存 GB")
                    .frame(maxWidth: .infinity)
                RingGauge(value: Double(mon.battery) / 100.0,
                          color: mon.charging ? T.amber : T.violet, center: "\(mon.battery)%", label: mon.charging ? "充电中" : "电池")
                    .frame(maxWidth: .infinity)
            }
            Divider().overlay(T.stroke)
            HStack {
                Text("当前性能模式").font(.system(size: 12)).foregroundStyle(T.sub)
                Spacer()
                Text(T.modeNames[min(2, max(0, mon.mode))])
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(T.modeColors[min(2, max(0, mon.mode))])
            }
            .font(.system(size: 12))
        }
    }

    // 控制来源（MHelper 已合并）
    private var mhelperCard: some View {
        GlassCard(title: "控制来源（MHelper 已合并）", icon: "checkmark.shield.fill", tint: T.accent) {
            HStack(alignment: .top, spacing: 10) {
                Text("性能模式 / 键盘背光 / 充电上限 / Fn Lock 已统一由 ASUS 控制台写入，并停用 MHelper 的登录项、在其运行时自动退出，避免两边来回抢设置。也可直接点菜单栏图标快捷调整。")
                    .font(.system(size: 10)).foregroundStyle(T.sub2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                StatusPill(icon: mon.mhelperRunning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                           text: mon.mhelperRunning ? "MHelper 运行中" : "已停用",
                           color: mon.mhelperRunning ? T.amber : T.accent)
            }
            Divider().overlay(T.stroke)
            HStack(spacing: 10) {
                Toggle(isOn: $mon.takeover) {
                    Text("自动停用 MHelper（保持同步）").font(.system(size: 11)).foregroundStyle(mon.takeover ? T.txt : T.sub)
                }
                .toggleStyle(.switch).tint(T.accent).controlSize(.mini)
                Spacer()
                Button {
                    mon.takeover = true
                    mon.enforceTakeover()
                    mon.applySavedOnLaunch()
                    flash("已接管控制权")
                } label: {
                    Text("立即接管").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(T.accent.opacity(0.16)))
                        .overlay(Capsule().stroke(T.accent.opacity(0.4), lineWidth: 1))
                        .foregroundStyle(T.accent)
                }
                .buttonStyle(.plain)
            }
            Toggle(isOn: $motionOn) {
                Text("玻璃粒子（可选动效）").font(.system(size: 11)).foregroundStyle(motionOn ? T.txt : T.sub)
            }
            .toggleStyle(.switch)
            .tint(T.accent)
            .controlSize(.mini)
        }
    }

    private var footer: some View {
        Text("风扇转速 / 温度：本机型 EC 不经 WMI 提供，无法实时读取。\n图形加速：Intel Iris Xe（8086:0xA7A0）已由 NootedGreen 驱动栈加速——VRAM 1536MB、Metal 2、HiDPI，H.264/HEVC 硬件解码已开启。")
            .font(.system(size: 10)).foregroundStyle(T.sub2)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.top, 2)
    }

    private var toastOverlay: some View {
        VStack {
            if !toast.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(T.accent)
                    Text(toast).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.txt)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().stroke(T.stroke, lineWidth: 1))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
    }

    // 动作
    private func brightStep(_ d: Double) {
        let now = Date()
        if now.timeIntervalSince(lastBright) < 0.12 { return }
        lastBright = now
        level = min(1.0, max(0.2, level + d))
        applyDim(); flash("亮度 \(Int(level * 100))%")
    }
    private func cycleMode(_ d: Int) {
        mon.setMode(min(2, max(0, mon.mode + d)))
        flash("模式 \(T.modeNames[min(2, max(0, mon.mode))])")
    }
    private func applyDim() { OverlayDimmer.shared.apply(level: Float(level), warm: Float(warm)) }
    private func flash(_ s: String) {
        toastWork?.cancel()
        toast = s
        let w = DispatchWorkItem { if toast == s { toast = "" } }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: w)
    }
}

// MARK: - 状态栏面板（像 MHelper 一样在菜单栏直接调）
struct StatusBarPanel: View {
    @ObservedObject var mon: Monitor
    @Environment(\.openWindow) private var openWindow

    private func applyPreset(_ l: Double, _ w: Double) {
        UserDefaults.standard.set(l, forKey: "level")
        UserDefaults.standard.set(w, forKey: "warm")
        OverlayDimmer.shared.apply(level: Float(l), warm: Float(w))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(T.accent)
                Text("ASUS 控制台").font(.system(size: 13, weight: .bold)).foregroundStyle(T.txt)
                Spacer()
                Text("CPU \(Int(mon.cpu))%").font(.system(size: 10, weight: .semibold)).foregroundStyle(T.sub)
            }
            group("性能模式") {
                Picker("", selection: Binding(get: { mon.mode }, set: { mon.setMode($0) })) {
                    Text("静音").tag(0); Text("均衡").tag(1); Text("性能").tag(2)
                }.pickerStyle(.segmented).labelsHidden()
            }
            group("键盘背光") {
                Picker("", selection: Binding(get: { mon.kbd }, set: { mon.setKbd($0) })) {
                    Text("关").tag(0); Text("低").tag(1); Text("中").tag(2); Text("高").tag(3)
                }.pickerStyle(.segmented).labelsHidden()
            }
            group("充电上限") {
                Picker("", selection: Binding(get: { mon.charge }, set: { mon.setCharge($0) })) {
                    Text("100%").tag(100); Text("80%").tag(80); Text("60%").tag(60)
                }.pickerStyle(.segmented).labelsHidden()
            }
            group("亮度 / 护眼") {
                HStack(spacing: 6) {
                    panelButton("白天") { applyPreset(1.0, 0.0) }
                    panelButton("柔和") { applyPreset(0.82, 0.12) }
                    panelButton("夜间") { applyPreset(0.6, 0.65) }
                }
            }
            Divider().overlay(T.stroke)
            HStack {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    if let w = NSApp.windows.first(where: { !($0 is OverlayWindow) && $0.isVisible }) {
                        w.level = .normal
                        w.makeKeyAndOrderFront(nil)
                    } else {
                        openWindow(id: "main")
                    }
                } label: { Text("打开控制台").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.accent) }
                    .buttonStyle(.plain)
                Spacer()
                Button { NSApp.terminate(nil) } label: { Text("退出").font(.system(size: 11)).foregroundStyle(T.sub) }
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(T.bg1)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.sub)
            content()
        }
    }

    private func panelButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(T.stroke, lineWidth: 1))
                .foregroundStyle(T.txt)
        }.buttonStyle(.plain)
    }
}

// MARK: - 菜单栏图标（常驻，负责接收“显示主窗口”事件后重建窗口）
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Image(systemName: "slider.horizontal.3")
            .onReceive(NotificationCenter.default.publisher(for: .asusShowMain)) { _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
    }
}

// MARK: - App
class AppDelegate: NSObject, NSApplicationDelegate {
    private var fittedOnce = false
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // 菜单栏常驻：accessory 策略不占 Dock、不显示 App 菜单栏，只留状态栏图标
        NSApp.setActivationPolicy(.accessory)
        Monitor.shared.applySavedOnLaunch()
        Monitor.shared.enforceTakeover()
        HotkeyTap.shared.start()
        HIDConsumerTap.shared.start()
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeMain(_:)),
                                               name: NSWindow.didBecomeMainNotification, object: nil)
    }
    @objc private func windowDidBecomeMain(_ n: Notification) {
        guard !fittedOnce, let w = n.object as? NSWindow, !(w is OverlayWindow) else { return }
        fittedOnce = true
        fit(w)
    }
    // 统一初始窗口尺寸，避免旧版保存的过大窗口超出屏幕；之后仍可自由缩放
    private func fit(_ win: NSWindow) {
        guard let scr = NSScreen.main else { return }
        let vis = scr.visibleFrame
        let h = min(760, vis.height - 40)
        let w: CGFloat = 520
        win.setFrame(NSRect(x: vis.midX - w / 2, y: vis.midY - h / 2, width: w, height: h), display: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .asusShowMain, object: nil)
        return true
    }
    func applicationWillTerminate(_ n: Notification) { OverlayDimmer.shared.reset() }
}

@main
struct AsusConsoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("ASUS 控制台", id: "main") { ContentView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentMinSize)
            .defaultSize(width: 520, height: 800)
            .defaultLaunchBehavior(.suppressed)
            .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra {
            StatusBarPanel(mon: Monitor.shared)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}
