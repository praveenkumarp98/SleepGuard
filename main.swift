// SleepGuard — keeps the Mac awake (lid closed too) for a time you choose, with a battery cutoff.
// Every block ends: timer, battery limit, charger unplugged, Stop, or Quit.
// Lives in the menu bar; opening the app shows its window (and a Dock icon while the window is open).
import AppKit
import Combine
import IOKit
import IOKit.ps
import ServiceManagement

// MARK: - Reading the Mac's state (no admin needed)

enum Mac {
    static func rootProp(_ key: String) -> Any? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("IOPMrootDomain"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        return IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
    /// Set by `--snapshot` so README screenshots show a clean "sleep allowed" state.
    static var demo = false
    static var demoSleepDisabled = false
    static var sleepDisabled: Bool { demo ? demoSleepDisabled : (rootProp("SleepDisabled") as? Bool) ?? false }
    static var lidClosed: Bool { demo ? false : (rootProp("AppleClamshellState") as? Bool) ?? false }
    /// False when docked (external display + power), where a closed lid keeps the Mac awake anyway.
    static var lidCausesSleep: Bool { (rootProp("AppleClamshellCausesSleep") as? Bool) ?? true }

    static var battery: (percent: Int, onAC: Bool)? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (cur * 100 / max, d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

// MARK: - Changing sleep (admin needed)

enum Power {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Tries passwordless sudo first (the sudoers line), then the macOS admin prompt if `interactive`.
    static func setSleepDisabled(_ on: Bool, interactive: Bool) -> Bool {
        let v = on ? "1" : "0"
        if run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", v]) { return true }
        guard interactive else { return false }
        NSApp.activate(ignoringOtherApps: true)
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"/usr/bin/pmset -a disablesleep \(v)\" with administrator privileges")?
            .executeAndReturnError(&err)
        return err == nil
    }

    /// Whether the sudoers rule is installed (no password needed to switch sleep off/on).
    static var canRestoreWithoutPassword: Bool {
        run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"])
            && run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"])
    }

    /// One admin prompt: writes /etc/sudoers.d/sleepguard allowing only `pmset -a disablesleep 0|1` without a password.
    static func installSudoers() -> Bool {
        let rule = """
        # Installed by SleepGuard: lets it switch sleep off/on without a password. Remove this file to undo.
        \(NSUserName()) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1

        """
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sleepguard.sudoers")
        guard (try? rule.write(to: tmp, atomically: true, encoding: .utf8)) != nil else { return false }
        let cmd = "/usr/sbin/visudo -cf '\(tmp.path)' && /usr/bin/install -m 0440 -o root -g wheel '\(tmp.path)' /etc/sudoers.d/sleepguard"
        NSApp.activate(ignoringOtherApps: true)
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(cmd)\" with administrator privileges")?.executeAndReturnError(&err)
        try? FileManager.default.removeItem(at: tmp)
        return err == nil && canRestoreWithoutPassword
    }

    static func sleepNow() { run("/usr/bin/pmset", ["sleepnow"]) }
}

// MARK: - Fail-safe job

/// Every 60 s: if sleep is blocked and SleepGuard isn't running (crash, force-quit, raw `sudo pmset`),
/// turn sleep back on. The app writes and loads this launchd job itself on each launch, so downloaded
/// copies get it too. The script is written from this string (not copied from the bundle), so it never
/// carries a download's quarantine flag.
enum FailSafe {
    static let label = "local.sleepguard.failsafe"
    static let script = """
    #!/bin/sh
    # SleepGuard fail-safe, run every 60 s by launchd. If sleep is blocked while SleepGuard
    # isn't running (crash, force-quit, or a raw `sudo pmset`), turn sleep back on.
    /usr/sbin/ioreg -r -n IOPMrootDomain -d 1 | /usr/bin/grep -q '"SleepDisabled" = Yes' || exit 0
    /usr/bin/pgrep -xq SleepGuard && exit 0
    /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0

    """

    static func install() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent("Library/Application Support/SleepGuard")
        let scriptURL = dir.appendingPathComponent("failsafe.sh")
        let plistURL = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
        let plist: [String: Any] = ["Label": label, "ProgramArguments": ["/bin/sh", scriptURL.path],
                                    "StartInterval": 60, "RunAtLoad": true]
        guard let plistData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        let domain = "gui/\(getuid())"
        let upToDate = (try? String(contentsOf: scriptURL, encoding: .utf8)) == script
            && (try? Data(contentsOf: plistURL)) == plistData
        if upToDate && Power.run("/bin/launchctl", ["print", "\(domain)/\(label)"]) { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? plistData.write(to: plistURL)
        Power.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        Power.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
    }
}

// MARK: - Icons

/// SF Symbol as a template image, so it follows light/dark mode and the menu's highlight colour.
func symbol(_ name: String?) -> NSImage? {
    guard let name, let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    img.isTemplate = true
    return img
}

/// The chosen sleep emoji (💤 or 😴), optionally crossed out with a red slash, like a no-entry sign.
func sleepEmoji(_ emoji: String, crossed: Bool, size: CGFloat = 18, dimmed: Bool = false) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        let k = size / 18
        let a = CGPoint(x: 2 * k, y: 16 * k), b = CGPoint(x: 16 * k, y: 2 * k)
        ctx.setAlpha(dimmed ? 0.55 : 1)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let s = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: size * 0.8)])
        let sz = s.size()
        s.draw(at: NSPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2))
        if crossed {
            ctx.setLineCap(.round)
            ctx.setBlendMode(.destinationOut)
            ctx.setLineWidth(4.4 * k); ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            ctx.setBlendMode(.normal)
            ctx.setStrokeColor(NSColor.systemRed.cgColor)
            ctx.setLineWidth(2.2 * k); ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        }
        ctx.endTransparencyLayer()
        return true
    }
}

func batterySymbol(_ pct: Int, onAC: Bool) -> String {
    if onAC { return "battery.100percent.bolt" }
    if pct < 13 { return "battery.0percent" }
    if pct < 38 { return "battery.25percent" }
    if pct < 63 { return "battery.50percent" }
    if pct < 88 { return "battery.75percent" }
    return "battery.100percent"
}

// MARK: - Menu helpers

final class Item: NSMenuItem {
    private var handler: () -> Void = {}
    convenience init(_ title: String, symbol name: String? = nil, checked: Bool = false, _ handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.handler = handler
        image = symbol(name)
        state = checked ? .on : .off
    }
    @objc private func fire() { handler() }
}

func info(_ title: String, symbol name: String? = nil) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    i.image = symbol(name)
    i.isEnabled = false
    return i
}

/// Bold, non-greyed status line at the top of the menu.
func header(_ title: String, image: NSImage?) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    i.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
    i.image = image
    return i
}

// MARK: - Formatting

func formatLeft(_ seconds: TimeInterval) -> String {
    let m = max(0, Int((seconds / 60).rounded(.up)))
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}

/// 90 → "1:30", 30 → "0:30" (the duration field's format).
func formatHM(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }

/// 5045 s → "1:24:05", 125 s → "2:05".
func formatClock(_ seconds: TimeInterval) -> String {
    let s = max(0, Int(seconds.rounded(.up)))
    let h = s / 3600, m = s % 3600 / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

/// "90" → 90 min, "1:30" → 90, "2 mins" → 2, "2h" / "2 hours" → 120, "2h30" / "1 hr 30 min" → 150.
func parseMinutes(_ s: String) -> Int? {
    let t = s.lowercased().trimmingCharacters(in: .whitespaces)
    if let n = Int(t) { return n }
    if t.contains(":") {
        let p = t.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count == 2, let h = p[0], let m = p[1] else { return nil }
        return h * 60 + m
    }
    // Optional hours part, then optional minutes part; the minutes unit may be left off ("2h30").
    let pattern = #"^(?:(\d+)\s*(?:h|hr|hrs|hour|hours))?\s*(?:(\d+)\s*(?:m|min|mins|minute|minutes)?)?$"#
    guard let re = try? NSRegularExpression(pattern: pattern),
          let match = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
    func group(_ i: Int) -> Int? {
        Range(match.range(at: i), in: t).flatMap { Int(t[$0]) }
    }
    let h = group(1), m = group(2)
    guard h != nil || m != nil else { return nil }
    return (h ?? 0) * 60 + (m ?? 0)
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, ObservableObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let defaults = UserDefaults.standard
    @Published var endsAt: Date?
    @Published var startedAt: Date?
    @Published var lastEnded: String?
    @Published var restoreFailed = false
    @Published var setupDone = true
    /// The duration field in the window ("1:30"); presets and menu starts write into it too.
    @Published var durationText = UserDefaults.standard.string(forKey: "lastCustom") ?? "1:00"
    var lastOnAC = true
    var activity: NSObjectProtocol?
    var window: NSWindow?
    var confirmedQuit = false

    var batteryLimit: Int {
        get { defaults.object(forKey: "batteryLimit") as? Int ?? 20 }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "batteryLimit") }
    }
    var stopOnUnplug: Bool {
        get { defaults.bool(forKey: "stopOnUnplug") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "stopOnUnplug") }
    }
    /// "💤" or "😴" — the menu bar icon.
    var emoji: String {
        get { defaults.string(forKey: "emoji") ?? "💤" }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "emoji"); refreshIcon() }
    }
    var openAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    var launchedAtLogin: Bool {
        guard let ev = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return ev.eventID == AEEventID(kAEOpenApplication)
            && ev.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        // Keep the 5 s check running while the lid is closed (no App Nap); idle sleep is still allowed.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Watching the sleep-block timer")

        // A block SleepGuard didn't start (raw `sudo pmset`, or left over from a crash) shows a ⚠️ state
        // and is undone when the lid closes — see check().

        if !CommandLine.arguments.contains("--snapshot") {
            FailSafe.install()
            if !defaults.bool(forKey: "loginSetUp") {
                defaults.set(true, forKey: "loginSetUp")
                try? SMAppService.mainApp.register()
            }
        }

        buildMainMenu()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        lastOnAC = Mac.battery?.onAC ?? true
        setupDone = Power.canRestoreWithoutPassword
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        refreshIcon()
        if !launchedAtLogin { showWindow() }
    }

    /// Opening the app again (Dock, Spotlight, Finder, `open`) shows its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    /// ⌘Q in the window (or Quit from the Dock) asks first: quitting removes the 💤 from the menu bar
    /// until the app is opened again, which is easy to do by accident when you only meant to close the window.
    /// The 💤 menu's "Quit SleepGuard" doesn't ask, and logging out or shutting down never waits on this.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if confirmedQuit || isSystemQuit { return .terminateNow }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Quit SleepGuard?"
        a.informativeText = """
        The 💤 icon leaves the menu bar until you open SleepGuard again\(endsAt != nil ? ", and the running block ends" : ""). \
        To keep it in the menu bar, just close the window (⌘W).
        """
        enum Choice { case closeWindow, quit, cancel }
        let choices: [Choice] = window?.isVisible == true ? [.closeWindow, .quit, .cancel] : [.quit, .cancel]
        for c in choices {
            a.addButton(withTitle: c == .closeWindow ? "Close Window" : c == .quit ? "Quit SleepGuard" : "Cancel")
        }
        let index = a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        switch choices.indices.contains(index) ? choices[index] : .cancel {
        case .closeWindow:
            window?.performClose(nil)
            return .terminateCancel
        case .quit:
            if endsAt != nil { restore(reason: "Quit", byUser: true) }
            return .terminateNow
        case .cancel:
            return .terminateCancel
        }
    }

    /// True when macOS is quitting apps for a log-out, restart or shutdown.
    var isSystemQuit: Bool {
        guard let ev = NSAppleEventManager.shared().currentAppleEvent,
              ev.eventClass == AEEventClass(kCoreEventClass), ev.eventID == AEEventID(kAEQuitApplication) else { return false }
        return ev.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
    }

    func applicationWillTerminate(_ n: Notification) {
        if endsAt != nil { _ = Power.setSleepDisabled(false, interactive: false) }
    }

    // MARK: Session

    func start(minutes: Int) {
        if let b = Mac.battery, !b.onAC, batteryLimit > 0, b.percent <= batteryLimit {
            alert("Battery is at \(b.percent)%, at or below your \(batteryLimit)% limit.",
                  "Plug in, or lower the limit under “Stop at battery”.")
            return
        }
        if endsAt == nil && !Mac.sleepDisabled {
            // Password at most once ever: the one-time setup, then never again.
            guard ensureSetup(), Power.setSleepDisabled(true, interactive: false) else { return }
        }
        durationText = formatHM(minutes)
        defaults.set(durationText, forKey: "lastCustom")
        startedAt = Date()
        endsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        lastEnded = nil
        refreshIcon()
    }

    /// Explains, then asks for the password once to install the sudoers rule. True if it's in place.
    func ensureSetup() -> Bool {
        if setupDone { return true }
        setupDone = Power.canRestoreWithoutPassword
        if setupDone { return true }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "One-time setup"
        a.informativeText = """
        SleepGuard needs your password once, to be allowed to switch sleep off and on. \
        After this it never asks again, and blocks can end on their own while the lid is closed.

        It adds one rule, /etc/sudoers.d/sleepguard, that only allows “pmset -a disablesleep 0” and “… 1”.
        """
        a.addButton(withTitle: "Continue")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        setupDone = Power.installSudoers()
        if !setupDone { alert("Setup didn’t complete.", "Nothing was changed. You can try again from the SleepGuard window.") }
        return setupDone
    }

    func extend(minutes: Int) {
        endsAt = endsAt?.addingTimeInterval(TimeInterval(minutes * 60))
        refreshIcon()
    }

    /// `byUser`: a click, so the password prompt is allowed as a fallback.
    /// Automatic restores never prompt (nobody may be looking, and a cancelled prompt must not repeat).
    func restore(reason: String, byUser: Bool = false) {
        endsAt = nil
        startedAt = nil
        lastEnded = reason
        if byUser && !setupDone { _ = ensureSetup() }
        // Falls back to a one-off password prompt only if you skipped setup and clicked yourself.
        restoreFailed = !Power.setSleepDisabled(false, interactive: byUser && !setupDone)
        if !restoreFailed && Mac.lidClosed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if Mac.lidClosed && Mac.lidCausesSleep { Power.sleepNow() }
            }
        }
        refreshIcon()
    }

    func check() {
        let bat = Mac.battery
        let unplugged = bat.map { !$0.onAC && lastOnAC } ?? false
        lastOnAC = bat?.onAC ?? true

        if let end = endsAt {
            if !Mac.sleepDisabled {
                endsAt = nil; startedAt = nil; lastEnded = "Sleep was turned back on outside SleepGuard"
            } else if Date() >= end {
                restore(reason: "Timer ended")
            } else if let b = bat, !b.onAC, batteryLimit > 0, b.percent <= batteryLimit {
                restore(reason: "Battery reached \(b.percent)%")
            } else if stopOnUnplug && unplugged {
                restore(reason: "Charger unplugged")
            }
        } else if Mac.sleepDisabled && Mac.lidClosed {
            // Blocked outside the app and the lid is closed: treat it as forgotten.
            restore(reason: "Lid closed while sleep was blocked outside SleepGuard")
        }
        refreshIcon()
    }

    // MARK: Menu bar

    func refreshIcon() {
        guard let button = item.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.imagePosition = .imageLeft
        if let end = endsAt {
            button.image = sleepEmoji(emoji, crossed: true)
            button.attributedTitle = NSAttributedString(string: " " + formatLeft(end.timeIntervalSinceNow), attributes: [.font: font])
            button.toolTip = "SleepGuard: keeping the Mac awake"
        } else if Mac.sleepDisabled {
            button.image = sleepEmoji(emoji, crossed: true)
            button.attributedTitle = NSAttributedString(string: " !", attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize), .foregroundColor: NSColor.systemOrange])
            button.toolTip = "SleepGuard: sleep is blocked outside the app"
        } else {
            button.image = sleepEmoji(emoji, crossed: false, dimmed: true)
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "SleepGuard: sleep allowed"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let timeFmt = DateFormatter()
        timeFmt.timeStyle = .short

        if let end = endsAt {
            menu.addItem(header("Keeping awake · \(formatLeft(end.timeIntervalSinceNow)) left", image: sleepEmoji(emoji, crossed: true)))
            menu.addItem(info("Sleep comes back at \(timeFmt.string(from: end))", symbol: "clock"))
        } else if Mac.sleepDisabled {
            menu.addItem(header("Sleep is blocked outside SleepGuard", image: sleepEmoji(emoji, crossed: true)))
            menu.addItem(info("It turns back on when you close the lid", symbol: "laptopcomputer"))
        } else {
            menu.addItem(header("Sleep allowed", image: sleepEmoji(emoji, crossed: false)))
        }
        if let b = Mac.battery {
            menu.addItem(info("Battery \(b.percent)% · \(b.onAC ? "charger connected" : "on battery")",
                              symbol: batterySymbol(b.percent, onAC: b.onAC)))
        }
        if let why = lastEnded { menu.addItem(info("Last block ended: \(why)", symbol: "clock.arrow.circlepath")) }
        if restoreFailed || !setupDone {
            menu.addItem(info("Setup needed so blocks can end with the lid closed", symbol: "lock.trianglebadge.exclamationmark"))
        }
        menu.addItem(.separator())

        if endsAt != nil {
            menu.addItem(Item("Add 30 minutes", symbol: "plus.circle") { self.extend(minutes: 30) })
            menu.addItem(Item("Add 1 hour", symbol: "plus.circle") { self.extend(minutes: 60) })
            menu.addItem(Item("Stop now (allow sleep)", symbol: "stop.circle") { self.restore(reason: "Stopped by you", byUser: true) })
        } else {
            if Mac.sleepDisabled {
                menu.addItem(Item("Turn sleep back on", symbol: "moon.zzz") { self.restore(reason: "Turned back on by you", byUser: true) })
                menu.addItem(.separator())
            }
            menu.addItem(NSMenuItem.sectionHeader(title: "Keep awake, even with the lid closed"))
            for (label, mins) in [("30 minutes", 30), ("1 hour", 60), ("2 hours", 120), ("4 hours", 240)] {
                menu.addItem(Item(label, symbol: "timer") { self.start(minutes: mins) })
            }
            menu.addItem(Item("Custom…", symbol: "slider.horizontal.3") { self.askCustom() })
        }
        menu.addItem(.separator())

        menu.addItem(NSMenuItem.sectionHeader(title: "Safety"))
        let battery = NSMenu()
        for pct in [0, 10, 15, 20, 25, 30, 40, 50] {
            battery.addItem(Item(pct == 0 ? "Off" : "\(pct)%", checked: batteryLimit == pct) { self.batteryLimit = pct })
        }
        let batteryItem = NSMenuItem(title: "Stop at battery: \(batteryLimit == 0 ? "Off" : "\(batteryLimit)%")", action: nil, keyEquivalent: "")
        batteryItem.image = symbol("battery.25percent")
        batteryItem.submenu = battery
        menu.addItem(batteryItem)
        menu.addItem(Item("Stop when charger is unplugged", symbol: "powerplug", checked: stopOnUnplug) { self.stopOnUnplug.toggle() })
        menu.addItem(.separator())
        menu.addItem(Item("Open SleepGuard…", symbol: "macwindow") { self.showWindow() })
        menu.addItem(Item("Quit SleepGuard (allows sleep)", symbol: "xmark.circle") { self.quit() })
    }

    func askCustom() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Keep awake for how long?"
        a.informativeText = "Examples: 45, 1:30, 2h, 2h30 (max 24h)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = defaults.string(forKey: "lastCustom") ?? "1:30"
        a.accessoryView = field
        a.addButton(withTitle: "Start")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        guard let m = parseMinutes(field.stringValue), m > 0, m <= 24 * 60 else {
            alert("Couldn’t read “\(field.stringValue)”.", "Use minutes (45), h:mm (1:30) or hours (2h).")
            return
        }
        defaults.set(field.stringValue, forKey: "lastCustom")
        start(minutes: m)
    }

    // MARK: App-level actions

    func toggleLogin() {
        objectWillChange.send()
        do {
            if openAtLogin { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            alert("Couldn’t change Open at login.", error.localizedDescription)
        }
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Keeps your Mac awake, lid closed too, for as long as you choose. Never forever.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]),
        ])
    }

    /// The 💤 menu's "Quit SleepGuard (allows sleep)": already explicit, so no confirmation.
    func quit() {
        if endsAt != nil { restore(reason: "Quit", byUser: true) }
        confirmedQuit = true
        NSApp.terminate(nil)
    }

    /// The menu bar menus shown while the window is open (app, Edit for the text field, Window).
    func buildMainMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let top = NSMenuItem()
            let sub = NSMenu(title: title)
            items.forEach(sub.addItem)
            top.submenu = sub
            main.addItem(top)
        }
        add("SleepGuard", [
            Item("About SleepGuard") { self.showAbout() },
            .separator(),
            NSMenuItem(title: "Hide SleepGuard", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            .separator(),
            // Standard terminate, so ⌘Q goes through applicationShouldTerminate and asks first.
            NSMenuItem(title: "Quit SleepGuard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ])
        add("Edit", [
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        add("Window", [
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
        ])
        NSApp.mainMenu = main
    }

    func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

// MARK: - Entry

if CommandLine.arguments.contains("--status") {
    let b = Mac.battery
    print("sleepDisabled=\(Mac.sleepDisabled) lidClosed=\(Mac.lidClosed) lidCausesSleep=\(Mac.lidCausesSleep) "
          + "battery=\(b.map { "\($0.percent)%" } ?? "none") onAC=\(b?.onAC ?? true) setupDone=\(Power.canRestoreWithoutPassword)")
    print("parse: 45→\(parseMinutes("45")!) 1:30→\(parseMinutes("1:30")!) 2h→\(parseMinutes("2h")!) "
          + "2h30→\(parseMinutes("2h30")!) clock(5045)=\(formatClock(5045)) clock(125)=\(formatClock(125))")
    exit(0)
}

// Used by uninstall.sh: removes SleepGuard from Login Items.
if CommandLine.arguments.contains("--unregister-login") {
    try? SMAppService.mainApp.unregister()
    exit(0)
}

let app = NSApplication.shared
let delegate = App()

// Dev aid: `SleepGuard --snapshot <dir>` renders the window in light and dark mode to PNGs, then exits.
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let dir = CommandLine.arguments[i + 1]
    Mac.demo = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        delegate.setupDone = true
        delegate.lastEnded = nil
        delegate.durationText = "1:00"
        func shoot(_ name: String, _ look: NSAppearance.Name) {
            delegate.window?.appearance = NSAppearance(named: look)
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            guard let frame = delegate.window?.contentView?.superview,
                  let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/window-\(name).png"))
        }
        shoot("now-light", .aqua); shoot("now-dark", .darkAqua)
        // Simulated running block (display only; pmset is not touched).
        Mac.demoSleepDisabled = true
        for (name, look) in [("active-light", NSAppearance.Name.aqua), ("active-dark", .darkAqua)] {
            // Same frame in both themes: 1:24:05 left of a 1:44:05 block.
            delegate.startedAt = Date().addingTimeInterval(-1200)
            delegate.endsAt = Date().addingTimeInterval(5045 + 0.9)
            shoot(name, look)
        }
        exit(0)
    }
}
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
