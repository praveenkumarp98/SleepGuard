// SleepGuard's window. Standard macOS look: system accent colour, grouped cards like System Settings,
// SF Mono for numbers and live system readouts. Follows light/dark automatically.
import AppKit
import SwiftUI

extension App {
    func showWindow() {
        if window == nil {
            let hosting = NSHostingController(rootView: MainView(app: self))
            hosting.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: hosting)
            w.title = "SleepGuard"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        setupDone = Power.canRestoreWithoutPassword
        // Dock icon only while the window is open; the menu bar item is always there.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

enum Status {
    case allowed, blocking, outside
    var label: String {
        switch self {
        case .allowed: return "SLEEP ALLOWED"
        case .blocking: return "KEEPING AWAKE"
        case .outside: return "BLOCKED OUTSIDE APP"
        }
    }
    var dot: Color {
        switch self {
        case .allowed: return .green
        case .blocking: return .accentColor
        case .outside: return .yellow
        }
    }
}

let mono = Font.system(.callout, design: .monospaced)

struct MainView: View {
    @ObservedObject var app: App
    @State private var inputError: String?
    let presets = [30, 60, 120, 240]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status: Status = app.endsAt != nil ? .blocking : (Mac.sleepDisabled ? .outside : .allowed)
            VStack(alignment: .leading, spacing: 16) {
                titleRow(status)
                card { StatusDial(app: app, now: context.date, status: status).frame(maxWidth: .infinity).padding(.vertical, 6) }
                if status == .blocking { sessionCard } else { durationCard(status) }
                if !app.setupDone || app.restoreFailed { setupCard }
                section("System") { systemCard(now: context.date) }
                section("Settings") { settingsCard }
                if let why = app.lastEnded {
                    Text("Last block ended: \(why)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 18)
            .frame(width: 420)
        }
    }

    // MARK: Pieces

    func titleRow(_ status: Status) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
            Text("SleepGuard").font(.title3.weight(.semibold))
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(status.dot).frame(width: 7, height: 7)
                Text(status.label).font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(0.8)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.quaternary))
        }
    }

    /// Presets write into the field; Start runs whatever the field says.
    func durationCard(_ status: Status) -> some View {
        let selected = parseMinutes(app.durationText)
        return section("Keep awake for") {
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: Binding<Int>(
                        get: { presets.contains(selected ?? -1) ? selected! : -1 },
                        set: { if $0 > 0 { app.durationText = formatHM($0); inputError = nil } })) {
                        Text("30m").tag(30)
                        Text("1h").tag(60)
                        Text("2h").tag(120)
                        Text("4h").tag(240)
                        Text("Custom").tag(-1)
                    }
                    .labelsHidden().pickerStyle(.segmented)
                    HStack(spacing: 8) {
                        TextField("h:mm", text: $app.durationText)
                            .font(mono)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(startFromField)
                        Text("h:mm · 45 · 2h").font(.caption).foregroundStyle(.secondary).fixedSize()
                        Button("Start", action: startFromField)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                    if let e = inputError { Text(e).font(.caption).foregroundStyle(.red) }
                    if status == .outside {
                        Divider()
                        HStack {
                            Text("Sleep is blocked by something else.").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Allow Sleep") { app.restore(reason: "Turned back on by you", byUser: true) }
                        }
                    }
                }
            }
        }
    }

    func startFromField() {
        guard let m = parseMinutes(app.durationText), m > 0, m <= 24 * 60 else {
            inputError = "Use h:mm (1:30), minutes (45) or hours (2h), up to 24h."
            return
        }
        inputError = nil
        app.start(minutes: m)
    }

    var sessionCard: some View {
        section("Session") {
            card {
                HStack(spacing: 8) {
                    Button("+30m") { app.extend(minutes: 30) }
                    Button("+1h") { app.extend(minutes: 60) }
                    Spacer()
                    Button("Stop", role: .destructive) { app.restore(reason: "Stopped by you", byUser: true) }
                        .keyboardShortcut(".", modifiers: .command)
                }
                .font(mono)
                .controlSize(.large)
            }
        }
    }

    var setupCard: some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("One-time setup").font(.headline)
                    Text("Enter your password once so SleepGuard can switch sleep off and on, and end blocks on its own with the lid closed. It never asks again.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Set Up…") { _ = app.ensureSetup() }
            }
        }
    }

    func systemCard(now: Date) -> some View {
        card {
            VStack(spacing: 6) {
                readout("pmset disablesleep", Mac.sleepDisabled ? "1" : "0")
                readout("lid", Mac.lidClosed ? "closed" : "open")
                if let b = Mac.battery {
                    readout("power", "\(b.onAC ? "AC" : "battery") · \(b.percent)%")
                }
                readout("sleep returns", app.endsAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                readout("passwordless", app.setupDone ? "yes" : "not set up")
            }
        }
    }

    func readout(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(mono)
    }

    var settingsCard: some View {
        card {
            VStack(spacing: 10) {
                row("Stop at battery") {
                    Picker("", selection: Binding(get: { app.batteryLimit }, set: { app.batteryLimit = $0 })) {
                        Text("Off").tag(0)
                        ForEach([10, 15, 20, 25, 30, 40, 50], id: \.self) { Text("\($0)%").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                Divider()
                row("Stop when charger is unplugged") {
                    Toggle("", isOn: Binding(get: { app.stopOnUnplug }, set: { app.stopOnUnplug = $0 }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                row("Open at login") {
                    Toggle("", isOn: Binding(get: { app.openAtLogin }, set: { _ in app.toggleLogin() }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                row("Menu bar icon") {
                    Picker("", selection: Binding(get: { app.emoji }, set: { app.emoji = $0 })) {
                        Text("💤").tag("💤")
                        Text("😴").tag("😴")
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
        }
    }

    // MARK: Layout helpers

    func row<C: View>(_ title: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack { Text(title); Spacer(); control() }
    }

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            content()
        }
    }

    /// A System Settings–style grouped card.
    func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

/// Slim ring in the system accent colour; SF Mono countdown. Idle shows the selected duration, dimmed.
struct StatusDial: View {
    @ObservedObject var app: App
    let now: Date
    let status: Status

    var progress: Double {
        guard let s = app.startedAt, let e = app.endsAt, e > s else { return 0 }
        return min(1, max(0, e.timeIntervalSince(now) / e.timeIntervalSince(s)))
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 6)
            // Drawn only while blocking, so it appears in place (no sweep-in from 0) and then ticks down smoothly.
            if status == .blocking {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }
            VStack(spacing: 4) {
                switch status {
                case .blocking:
                    Text(formatClock(app.endsAt!.timeIntervalSince(now)))
                        .font(.system(size: 40, weight: .light, design: .monospaced))
                    Text("remaining").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                case .outside:
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 28, weight: .light)).foregroundStyle(.yellow)
                    Text("blocked externally").font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                case .allowed:
                    Text(parseMinutes(app.durationText).map { formatClock(TimeInterval($0 * 60)) } ?? "--:--")
                        .font(.system(size: 40, weight: .light, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text("ready").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 190, height: 190)
    }
}
