import AppKit
import Foundation
import UserNotifications

private struct SessionState: Decodable {
    let sessionId: String
    let turnId: String?
    let project: String
    let cwd: String
    let branch: String?
    let surface: String?
    let hostBundle: String?
    let model: String?
    let permissionMode: String?
    let tool: String?
    let state: String
    let label: String
    let started: Bool
    let startedAt: Int?
    let updatedAt: Int
    let contextPercent: Int?
    let tokens: Int?
    let window: Int?
}

private struct ContextMetric: Decodable {
    let contextPercent: Int?
    let tokens: Int?
    let window: Int?
    let contextSource: String?
    let contextUpdatedAt: Int?
}

private struct LimitWindowValue {
    let key: String
    let title: String
    let usedPercent: Int
    let durationMinutes: Int
    let resetsAt: Date?
}

private final class ControlBarController: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let decoder = JSONDecoder()
    private let fileManager = FileManager.default
    private let stateRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/control-bar", isDirectory: true)
    private var timer: Timer?
    private var iconTimer: Timer?
    private var iconPhase: CGFloat = 0
    private var iconState: ControlBarIconState = .idle
    private var iconStyle: ControlBarIconStyle = .gptKnot
    private var animationEnabled = true
    private var showStatusText = true
    private var showTurnTimer = false
    private var usePlayfulStatusWords = true
    private var sessionWord: [String: String] = [:]
    private var snapshotProcess: Process?
    private var contextProcess: Process?
    private var lastSnapshotRequest = Date.distantPast
    private var lastContextRequest = Date.distantPast
    private var previousSessionStates: [String: String]?
    private var observedContext: [String: ContextMetric] = [:]
    private var notifiedContextLevel: [String: Int] = [:]
    private var contextLevelsInitialized = false
    private var previousLimitLevels: [String: Int]?
    private var previousMCPHealth: [String: Bool]?
    private var contextWarningsEnabled = true
    private var limitWarningsEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let applicationIcon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = applicationIcon
        }
        menu.delegate = self
        statusItem.menu = menu
        if let button = statusItem.button {
            button.image = StatusIconRenderer.image(state: .idle, phase: 0)
            button.imagePosition = .imageLeading
            button.title = ""
        }
        if UserDefaults.standard.object(forKey: "animationEnabled") != nil {
            animationEnabled = UserDefaults.standard.bool(forKey: "animationEnabled")
        }
        if let rawStyle = UserDefaults.standard.string(forKey: "iconStyle"),
           let storedStyle = ControlBarIconStyle(rawValue: rawStyle) {
            iconStyle = storedStyle
        }
        if UserDefaults.standard.object(forKey: "showStatusText") != nil {
            showStatusText = UserDefaults.standard.bool(forKey: "showStatusText")
        }
        if UserDefaults.standard.object(forKey: "showTurnTimer") != nil {
            showTurnTimer = UserDefaults.standard.bool(forKey: "showTurnTimer")
        }
        if UserDefaults.standard.object(forKey: "usePlayfulStatusWords") != nil {
            usePlayfulStatusWords = UserDefaults.standard.bool(forKey: "usePlayfulStatusWords")
        }
        if UserDefaults.standard.object(forKey: "contextWarningsEnabled") != nil {
            contextWarningsEnabled = UserDefaults.standard.bool(forKey: "contextWarningsEnabled")
        }
        if UserDefaults.standard.object(forKey: "limitWarningsEnabled") != nil {
            limitWarningsEnabled = UserDefaults.standard.bool(forKey: "limitWarningsEnabled")
        }
        loadContextSnapshot()
        configureNotifications()
        refreshStatusItem()
        refreshSnapshotIfNeeded(force: false)
        refreshContextIfNeeded(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshStatusItem()
            self?.refreshSnapshotIfNeeded(force: false)
            self?.refreshContextIfNeeded(force: false)
        }
        if CommandLine.arguments.contains("--test-notification") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.sendGeneralNotification(
                    title: "Codex Control Bar is ready",
                    body: "Notifications and the application icon are configured correctly.",
                    identifier: "codex-control-bar-self-test"
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.terminate(nil) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        iconTimer?.invalidate()
        snapshotProcess?.terminate()
        contextProcess?.terminate()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func sessions() -> [SessionState] {
        let directory = stateRoot.appendingPathComponent("state.d", isDirectory: true)
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "json", let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(SessionState.self, from: data)
        }.sorted { left, right in
            if left.state == "permission" && right.state != "permission" { return true }
            if left.state != "permission" && right.state == "permission" { return false }
            return left.updatedAt > right.updatedAt
        }
    }

    private func refreshStatusItem() {
        let values = sessions()
        detectSessionTransitions(values)
        detectContextThresholds(values)
        detectLimitThresholds()
        detectMCPHealthChanges()
        let active = values.filter { ["thinking", "tool"].contains($0.state) }.count
        let waiting = values.filter { $0.state == "permission" }.count
        let state: ControlBarIconState
        if waiting > 0 {
            state = .permission
        } else if values.contains(where: { $0.state == "tool" }) {
            state = .tool
        } else if active > 0 {
            state = .thinking
        } else {
            state = .idle
        }
        updateIconAnimation(state)
        DispatchQueue.main.async { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            let title = self.statusBarTitle(values: values, state: state, active: active, waiting: waiting)
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            button.attributedTitle = NSAttributedString(
                string: title.isEmpty ? "" : " \(title)",
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                ]
            )
            button.toolTip = waiting > 0
                ? "Codex needs permission"
                : (active > 0 ? "Codex is working" : "Codex Control Bar")
        }
    }

    private func statusBarTitle(
        values: [SessionState], state: ControlBarIconState, active: Int, waiting: Int
    ) -> String {
        guard showStatusText || showTurnTimer else { return active > 1 ? "\(active)" : "" }
        let lead = values.first { $0.state == "permission" }
            ?? values.first { $0.state == "tool" }
            ?? values.first { $0.state == "thinking" }
        guard let lead else { return "" }

        let elapsed: Int
        if let startedAt = lead.startedAt, startedAt > 0 {
            elapsed = max(0, Int(Date().timeIntervalSince1970) - startedAt)
        } else {
            elapsed = 0
        }
        var parts: [String] = []
        if showStatusText {
            switch state {
            case .permission:
                parts.append("Waiting for permission")
            case .tool:
                let label = lead.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = (label.isEmpty ? "Working" : label)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".…"))
                parts.append(base + StatusPresentation.progressDots(second: Int(Date().timeIntervalSince1970)))
            case .thinking:
                let word = usePlayfulStatusWords ? (sessionWord[lead.sessionId] ?? "Thinking") : "Thinking"
                parts.append(word + StatusPresentation.progressDots(second: Int(Date().timeIntervalSince1970)))
            case .idle:
                break
            }
        }
        if showTurnTimer && elapsed > 0 && state != .permission {
            parts.append(duration(since: lead.startedAt ?? 0))
        }
        if waiting > 1 {
            parts.append("\(waiting) sessions")
        } else if active > 1 {
            parts.append("\(active) sessions")
        }
        return parts.joined(separator: "  ·  ")
    }

    private func updateIconAnimation(_ state: ControlBarIconState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let changed = self.iconState != state
            self.iconState = state
            if changed { self.iconPhase = 0 }
            let shouldAnimate = self.animationEnabled && state != .idle
            if shouldAnimate && self.iconTimer == nil {
                let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.iconPhase = (self.iconPhase + 1.0 / 40.0).truncatingRemainder(dividingBy: 1)
                    self.renderStatusIcon()
                }
                RunLoop.main.add(timer, forMode: .common)
                self.iconTimer = timer
            } else if !shouldAnimate {
                self.iconTimer?.invalidate()
                self.iconTimer = nil
            }
            if changed || !shouldAnimate { self.renderStatusIcon() }
        }
    }

    private func renderStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.image(state: iconState, phase: iconPhase, style: iconStyle)
        button.contentTintColor = nil
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        addHeader("SESSIONS")
        let values = sessions()
        if values.isEmpty {
            addDisplay("No local Codex sessions yet")
        } else {
            for session in values where session.started {
                let item = NSMenuItem()
                let model = SessionRowModel(
                    title: sessionTitle(session),
                    state: session.state,
                    subtitle: sessionSubtitle(session),
                    timer: sessionTimer(session),
                    contextPercent: contextMetric(for: session)?.contextPercent ?? session.contextPercent,
                    surface: session.surface,
                    tooltip: sessionTooltip(session, metric: contextMetric(for: session))
                )
                item.view = SessionMenuRow(model: model) { [weak self] in
                    self?.openSession(session)
                }
                menu.addItem(item)
            }
            if !values.contains(where: { $0.started }) {
                addDisplay("Sessions are open but idle")
            }
        }

        menu.addItem(.separator())
        addLimits()
        menu.addItem(.separator())
        addMCP()
        menu.addItem(.separator())
        addMonitorStatus()

        let refresh = NSMenuItem(title: "Refresh limits and MCP", action: #selector(forceRefresh), keyEquivalent: "r")
        refresh.target = self
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(refresh)

        let preferences = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        preferences.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        let preferencesMenu = NSMenu()
        let animation = NSMenuItem(title: "Animate menu bar icon", action: #selector(toggleAnimation(_:)), keyEquivalent: "")
        animation.target = self
        animation.state = animationEnabled ? .on : .off
        preferencesMenu.addItem(animation)
        let styleItem = NSMenuItem(title: "Animation style", action: nil, keyEquivalent: "")
        styleItem.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        let styleMenu = NSMenu()
        for style in ControlBarIconStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(chooseIconStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == iconStyle ? .on : .off
            styleMenu.addItem(item)
        }
        styleItem.submenu = styleMenu
        preferencesMenu.addItem(styleItem)
        preferencesMenu.addItem(.separator())
        let statusText = NSMenuItem(title: "Show status beside icon", action: #selector(toggleStatusText(_:)), keyEquivalent: "")
        statusText.target = self
        statusText.state = showStatusText ? .on : .off
        preferencesMenu.addItem(statusText)
        let turnTimer = NSMenuItem(title: "Show active turn timer", action: #selector(toggleTurnTimer(_:)), keyEquivalent: "")
        turnTimer.target = self
        turnTimer.state = showTurnTimer ? .on : .off
        preferencesMenu.addItem(turnTimer)
        let playfulWords = NSMenuItem(title: "Use playful thinking words", action: #selector(togglePlayfulWords(_:)), keyEquivalent: "")
        playfulWords.target = self
        playfulWords.state = usePlayfulStatusWords ? .on : .off
        preferencesMenu.addItem(playfulWords)
        let contextWarnings = NSMenuItem(title: "Context warnings at 75% and 90%", action: #selector(toggleContextWarnings(_:)), keyEquivalent: "")
        contextWarnings.target = self
        contextWarnings.state = contextWarningsEnabled ? .on : .off
        preferencesMenu.addItem(contextWarnings)
        let limitWarnings = NSMenuItem(title: "Limit warnings at 75% and 90%", action: #selector(toggleLimitWarnings(_:)), keyEquivalent: "")
        limitWarnings.target = self
        limitWarnings.state = limitWarningsEnabled ? .on : .off
        preferencesMenu.addItem(limitWarnings)
        preferences.submenu = preferencesMenu
        menu.addItem(preferences)

        let diagnostics = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        diagnostics.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: nil)
        let diagnosticsMenu = NSMenu()
        let state = NSMenuItem(title: "Open local state", action: #selector(openStateDirectory), keyEquivalent: "")
        state.target = self
        diagnosticsMenu.addItem(state)
        let testNotification = NSMenuItem(title: "Send test notification", action: #selector(sendTestNotification), keyEquivalent: "")
        testNotification.target = self
        diagnosticsMenu.addItem(testNotification)
        let version = NSMenuItem(title: "Version 0.7.0", action: nil, keyEquivalent: "")
        version.isEnabled = false
        diagnosticsMenu.addItem(version)
        diagnostics.submenu = diagnosticsMenu
        menu.addItem(diagnostics)

        let quit = NSMenuItem(title: "Quit Codex Control Bar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
    }

    private func sessionTitle(_ session: SessionState) -> String {
        let project = session.project.isEmpty ? "Codex" : session.project
        guard let branch = session.branch, !branch.isEmpty else { return project }
        return "\(project)  ·  \(branch)"
    }

    private func sessionSubtitle(_ session: SessionState) -> String {
        var parts = [session.label]
        if let model = session.model, !model.isEmpty { parts.append("Model: \(model)") }
        if let mode = session.permissionMode, !mode.isEmpty { parts.append("Permissions: \(mode)") }
        return parts.joined(separator: "  ·  ")
    }

    private func sessionTimer(_ session: SessionState) -> String? {
        guard let started = session.startedAt, started > 0,
              ["thinking", "tool"].contains(session.state) else { return nil }
        return duration(since: started)
    }

    private func sessionTooltip(_ session: SessionState, metric: ContextMetric?) -> String {
        var lines = [session.cwd]
        lines.append("Updated: \(relativeAge(since: session.updatedAt)) ago")
        if let branch = session.branch, !branch.isEmpty { lines.append("Branch: \(branch)") }
        if let surface = session.surface, !surface.isEmpty { lines.append("Surface: \(surface)") }
        if let model = session.model, !model.isEmpty { lines.append("Model: \(model)") }
        if let mode = session.permissionMode, !mode.isEmpty { lines.append("Permissions: \(mode)") }
        if let tokens = metric?.tokens ?? session.tokens, let window = metric?.window ?? session.window {
            lines.append("Context: \(tokens.formatted()) / \(window.formatted()) tokens")
        }
        if let source = metric?.contextSource { lines.append("Context source: \(source)") }
        if let updated = metric?.contextUpdatedAt { lines.append("Context measured: \(relativeAge(since: updated)) ago") }
        return lines.joined(separator: "\n")
    }

    private func contextMetric(for session: SessionState) -> ContextMetric? {
        observedContext[session.sessionId]
    }

    private func loadContextSnapshot() {
        let url = stateRoot.appendingPathComponent("context.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["sessions"] as? [String: Any]
        else { return }
        var result: [String: ContextMetric] = [:]
        for (sessionId, value) in rows {
            guard JSONSerialization.isValidJSONObject(value),
                  let rowData = try? JSONSerialization.data(withJSONObject: value),
                  let metric = try? decoder.decode(ContextMetric.self, from: rowData)
            else { continue }
            result[sessionId] = metric
        }
        observedContext = result
    }

    private func duration(since unixTime: Int) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince1970) - unixTime)
        if seconds < 60 { return "\(seconds)s" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func snapshot() -> [String: Any] {
        let url = stateRoot.appendingPathComponent("snapshot.json")
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return value
    }

    private func addLimits() {
        addHeader("LIMITS")
        let value = snapshot()
        if let error = value["error"] as? String {
            addDisplay("Unavailable: \(error)")
            return
        }
        let windows = limitWindows()
        guard !windows.isEmpty else {
            addDisplay("Not measured yet")
            return
        }
        for window in windows {
            let resetText = window.resetsAt.map { "Resets in " + resetCountdown(to: $0) }
            let item = NSMenuItem()
            let view = LimitMenuRow(title: window.title, percent: window.usedPercent, reset: resetText)
            view.toolTip = "Source: Codex App Server account/rateLimits/read"
            item.view = view
            menu.addItem(item)
        }
    }

    private func limitWindows() -> [LimitWindowValue] {
        let value = snapshot()
        guard let response = value["rateLimits"] as? [String: Any] else { return [] }
        var buckets: [(String, [String: Any])] = []
        if let byId = response["rateLimitsByLimitId"] as? [String: Any], !byId.isEmpty {
            for key in byId.keys.sorted() {
                if let bucket = byId[key] as? [String: Any] { buckets.append((key, bucket)) }
            }
        } else if let bucket = response["rateLimits"] as? [String: Any] {
            buckets.append(("codex", bucket))
        }
        var result: [LimitWindowValue] = []
        for (bucketId, bucket) in buckets {
            let backendName = bucket["limitName"] as? String
            let displayName = (backendName?.isEmpty == false ? backendName! : (bucketId == "codex" ? "Codex" : bucketId))
            for slot in ["primary", "secondary"] {
                guard let window = bucket[slot] as? [String: Any],
                      let used = number(window["usedPercent"])
                else { continue }
                let minutes = Int(number(window["windowDurationMins"]) ?? 0)
                let reset = number(window["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
                result.append(LimitWindowValue(
                    key: "\(bucketId).\(slot)",
                    title: "\(displayName) · \(windowLabel(minutes: minutes))",
                    usedPercent: max(0, min(100, Int(used.rounded()))),
                    durationMinutes: minutes,
                    resetsAt: reset
                ))
            }
        }
        return result.sorted {
            if $0.durationMinutes == $1.durationMinutes { return $0.title < $1.title }
            return $0.durationMinutes < $1.durationMinutes
        }
    }

    private func addMCP() {
        addHeader("MCP")
        let value = snapshot()
        guard let mcp = value["mcp"] as? [String: Any], let servers = mcp["data"] as? [[String: Any]] else {
            addDisplay("Not checked yet")
            return
        }
        if servers.isEmpty {
            addDisplay("No configured servers")
            return
        }
        for server in servers {
            let name = server["name"] as? String ?? "MCP"
            let tools = server["tools"] as? [String: Any] ?? [:]
            let auth = server["authStatus"] as? String ?? "unknown"
            let authLabel: String
            switch auth {
            case "bearerToken": authLabel = "Token auth"
            case "oAuth": authLabel = "OAuth"
            case "notLoggedIn": authLabel = "sign-in required"
            case "unsupported": authLabel = "Local process"
            default: authLabel = ""
            }
            let item = NSMenuItem()
            item.view = MCPMenuRow(
                name: name,
                tools: tools.count,
                status: authLabel,
                healthy: auth != "notLoggedIn" && auth != "unknown",
                details: mcpDetailsMenu(server: server)
            )
            menu.addItem(item)
        }
    }

    private func mcpDetailsMenu(server: [String: Any]) -> NSMenu {
        let menu = NSMenu()
        let name = server["name"] as? String ?? "MCP"
        if let info = server["serverInfo"] as? [String: Any] {
            let title = info["title"] as? String ?? info["name"] as? String ?? name
            let version = info["version"] as? String ?? ""
            let header = NSMenuItem(title: version.isEmpty ? title : "\(title) · \(version)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            if let description = info["description"] as? String, !description.isEmpty {
                header.toolTip = description
            }
            menu.addItem(.separator())
        }
        let tools = server["tools"] as? [String: Any] ?? [:]
        if tools.isEmpty {
            let empty = NSMenuItem(title: "No advertised tools", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for key in tools.keys.sorted() {
                let tool = tools[key] as? [String: Any] ?? [:]
                let title = tool["title"] as? String ?? tool["name"] as? String ?? key
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: "hammer", accessibilityDescription: nil)
                if let description = tool["description"] as? String, !description.isEmpty {
                    item.toolTip = "\(key)\n\(description)"
                } else {
                    item.toolTip = key
                }
                menu.addItem(item)
            }
        }
        let resources = (server["resources"] as? [Any])?.count ?? 0
        let templates = (server["resourceTemplates"] as? [Any])?.count ?? 0
        if resources + templates > 0 {
            menu.addItem(.separator())
            let summary = NSMenuItem(title: "\(resources) resources · \(templates) templates", action: nil, keyEquivalent: "")
            summary.isEnabled = false
            menu.addItem(summary)
        }
        return menu
    }

    private func addMonitorStatus() {
        let value = snapshot()
        let snapshotUpdated = number(value["updatedAt"]).map(Int.init)
        let latestSession = sessions().map(\.updatedAt).max()
        let latest = [snapshotUpdated, latestSession].compactMap { $0 }.max()
        let age = latest.map { max(0, Int(Date().timeIntervalSince1970) - $0) }
        let healthy = value["error"] == nil && (age.map { $0 < 600 } ?? false)
        let detail: String
        if let age {
            detail = "updated \(relativeDuration(age)) ago"
        } else {
            detail = "waiting for first update"
        }
        let item = NSMenuItem()
        item.view = MonitorStatusRow(
            title: healthy ? "Local monitor online" : "Data may be stale",
            detail: detail,
            healthy: healthy
        )
        menu.addItem(item)
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func windowLabel(minutes: Int) -> String {
        if minutes >= 1440 && minutes % 1440 == 0 { return "\(minutes / 1440)d" }
        if minutes >= 60 && minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private func relativeAge(since unixTime: Int) -> String {
        relativeDuration(max(0, Int(Date().timeIntervalSince1970) - unixTime))
    }

    private func relativeDuration(_ seconds: Int) -> String {
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }

    private func resetCountdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds < 3600 { return "\(max(1, seconds / 60))m" }
        if seconds < 86_400 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        return "\(seconds / 86_400)d \((seconds % 86_400) / 3600)h"
    }

    private func addHeader(_ title: String) {
        let symbol: String
        switch title {
        case "SESSIONS": symbol = "rectangle.stack.fill"
        case "LIMITS": symbol = "gauge.with.dots.needle.67percent"
        case "MCP": symbol = "shippingbox.fill"
        default: symbol = "circle.fill"
        }
        let item = NSMenuItem()
        item.view = SectionHeaderView(title: title, symbol: symbol)
        menu.addItem(item)
    }

    private func addDisplay(_ title: String) {
        let item = NSMenuItem()
        item.view = StaticMenuRow(text: title)
        menu.addItem(item)
    }

    private func refreshSnapshotIfNeeded(force: Bool) {
        guard snapshotProcess == nil else { return }
        if !force && Date().timeIntervalSince(lastSnapshotRequest) < 300 { return }
        guard let resourcePath = Bundle.main.resourcePath else { return }
        let script = URL(fileURLWithPath: resourcePath).appendingPathComponent("appserver_snapshot.py").path
        guard fileManager.fileExists(atPath: script) else { return }
        lastSnapshotRequest = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.snapshotProcess = nil
                self?.rebuildMenu()
            }
        }
        do {
            try process.run()
            snapshotProcess = process
        } catch {
            snapshotProcess = nil
        }
    }

    private func refreshContextIfNeeded(force: Bool) {
        guard contextProcess == nil else { return }
        if !force && Date().timeIntervalSince(lastContextRequest) < 15 { return }
        guard let resourcePath = Bundle.main.resourcePath else { return }
        let script = URL(fileURLWithPath: resourcePath).appendingPathComponent("context_snapshot.py").path
        guard fileManager.fileExists(atPath: script) else { return }
        lastContextRequest = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.contextProcess = nil
                self?.loadContextSnapshot()
            }
        }
        do {
            try process.run()
            contextProcess = process
        } catch {
            contextProcess = nil
        }
    }

    @objc private func forceRefresh() {
        refreshSnapshotIfNeeded(force: true)
    }

    @objc private func toggleAnimation(_ sender: NSMenuItem) {
        animationEnabled.toggle()
        UserDefaults.standard.set(animationEnabled, forKey: "animationEnabled")
        sender.state = animationEnabled ? .on : .off
        if !animationEnabled {
            iconTimer?.invalidate()
            iconTimer = nil
            iconPhase = 0
            renderStatusIcon()
        } else {
            let current = iconState
            iconState = .idle
            updateIconAnimation(current)
        }
    }

    @objc private func chooseIconStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = ControlBarIconStyle(rawValue: raw) else { return }
        iconStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: "iconStyle")
        iconPhase = 0
        renderStatusIcon()
        rebuildMenu()
    }

    @objc private func toggleStatusText(_ sender: NSMenuItem) {
        showStatusText.toggle()
        UserDefaults.standard.set(showStatusText, forKey: "showStatusText")
        sender.state = showStatusText ? .on : .off
        refreshStatusItem()
    }

    @objc private func toggleTurnTimer(_ sender: NSMenuItem) {
        showTurnTimer.toggle()
        UserDefaults.standard.set(showTurnTimer, forKey: "showTurnTimer")
        sender.state = showTurnTimer ? .on : .off
        refreshStatusItem()
    }

    @objc private func togglePlayfulWords(_ sender: NSMenuItem) {
        usePlayfulStatusWords.toggle()
        UserDefaults.standard.set(usePlayfulStatusWords, forKey: "usePlayfulStatusWords")
        sender.state = usePlayfulStatusWords ? .on : .off
        refreshStatusItem()
    }

    @objc private func toggleContextWarnings(_ sender: NSMenuItem) {
        contextWarningsEnabled.toggle()
        UserDefaults.standard.set(contextWarningsEnabled, forKey: "contextWarningsEnabled")
        sender.state = contextWarningsEnabled ? .on : .off
        if !contextWarningsEnabled { notifiedContextLevel.removeAll() }
    }

    @objc private func toggleLimitWarnings(_ sender: NSMenuItem) {
        limitWarningsEnabled.toggle()
        UserDefaults.standard.set(limitWarningsEnabled, forKey: "limitWarningsEnabled")
        sender.state = limitWarningsEnabled ? .on : .off
        if !limitWarningsEnabled { previousLimitLevels = nil }
    }

    private func openProject(path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func openSession(_ session: SessionState) {
        if session.surface != "APP",
           let bundle = session.hostBundle, !bundle.isEmpty,
           let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: application, configuration: configuration)
            return
        }
        if !session.sessionId.isEmpty,
           let escaped = session.sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "codex://threads/\(escaped)"),
           NSWorkspace.shared.open(url) {
            return
        }
        openProject(path: session.cwd)
    }

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func detectSessionTransitions(_ values: [SessionState]) {
        let current = Dictionary(uniqueKeysWithValues: values.map { ($0.sessionId, $0.state) })
        guard let previous = previousSessionStates else {
            for session in values where session.state == "thinking" {
                sessionWord[session.sessionId] = StatusPresentation.nextThinkingWord(previous: nil)
            }
            previousSessionStates = current
            return
        }
        for session in values {
            let oldState = previous[session.sessionId]
            if session.state == "thinking", oldState != "thinking" {
                sessionWord[session.sessionId] = StatusPresentation.nextThinkingWord(
                    previous: sessionWord[session.sessionId]
                )
            }
            guard let oldState, oldState != session.state else { continue }
            switch session.state {
            case "permission":
                sendNotification(
                    title: "Codex needs permission",
                    body: "\(session.project): review the pending action",
                    session: session
                )
            case "done" where ["thinking", "tool", "permission"].contains(oldState):
                sendNotification(
                    title: "Codex task completed",
                    body: session.project.isEmpty ? "The task is ready" : "\(session.project) is ready",
                    session: session
                )
            default:
                break
            }
        }
        let present = Set(current.keys)
        for sessionId in Array(sessionWord.keys) where !present.contains(sessionId) {
            sessionWord.removeValue(forKey: sessionId)
        }
        previousSessionStates = current
    }

    private func detectContextThresholds(_ values: [SessionState]) {
        guard contextWarningsEnabled else { return }
        if !contextLevelsInitialized {
            for session in values {
                let percent = contextMetric(for: session)?.contextPercent ?? session.contextPercent ?? 0
                notifiedContextLevel[session.sessionId] = percent >= 90 ? 90 : (percent >= 75 ? 75 : 0)
            }
            contextLevelsInitialized = true
            return
        }
        for session in values {
            guard let percent = contextMetric(for: session)?.contextPercent ?? session.contextPercent else { continue }
            let level = percent >= 90 ? 90 : (percent >= 75 ? 75 : 0)
            let previous = notifiedContextLevel[session.sessionId] ?? 0
            if level > previous {
                sendNotification(
                    title: level == 90 ? "Codex context almost full" : "Codex context is filling up",
                    body: "\(session.project): \(percent)% of the context window is used",
                    session: session
                )
            }
            notifiedContextLevel[session.sessionId] = level
        }
    }

    private func detectLimitThresholds() {
        guard limitWarningsEnabled else { return }
        let windows = limitWindows()
        let current = Dictionary(uniqueKeysWithValues: windows.map { window in
            (window.key, window.usedPercent >= 90 ? 90 : (window.usedPercent >= 75 ? 75 : 0))
        })
        guard let previous = previousLimitLevels else {
            previousLimitLevels = current
            return
        }
        for window in windows {
            let level = current[window.key] ?? 0
            if level > (previous[window.key] ?? 0) {
                sendGeneralNotification(
                    title: level == 90 ? "Codex limit almost exhausted" : "Codex usage limit warning",
                    body: "\(window.title): \(window.usedPercent)% used",
                    identifier: "limit-\(window.key)-\(level)"
                )
            }
        }
        previousLimitLevels = current
    }

    private func detectMCPHealthChanges() {
        let value = snapshot()
        guard let mcp = value["mcp"] as? [String: Any],
              let servers = mcp["data"] as? [[String: Any]]
        else { return }
        let current = Dictionary(uniqueKeysWithValues: servers.map { server in
            let name = server["name"] as? String ?? "MCP"
            let auth = server["authStatus"] as? String ?? "unknown"
            return (name, auth != "notLoggedIn" && auth != "unknown")
        })
        guard let previous = previousMCPHealth else {
            previousMCPHealth = current
            return
        }
        for (name, healthy) in current where previous[name] == true && !healthy {
            sendGeneralNotification(
                title: "MCP server needs attention",
                body: "\(name) is no longer ready",
                identifier: "mcp-unhealthy-\(name)"
            )
        }
        previousMCPHealth = current
    }

    private func sendNotification(title: String, body: String, session: SessionState) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["sessionId": session.sessionId, "cwd": session.cwd]
        let request = UNNotificationRequest(
            identifier: "\(session.sessionId)-\(session.state)-\(session.updatedAt)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func sendGeneralNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let sessionId = info["sessionId"] as? String ?? ""
        let cwd = info["cwd"] as? String ?? ""
        if !sessionId.isEmpty,
           let escaped = sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "codex://threads/\(escaped)"),
           NSWorkspace.shared.open(url) {
            completionHandler()
            return
        }
        openProject(path: cwd)
        completionHandler()
    }

    @objc private func openStateDirectory() {
        try? fileManager.createDirectory(at: stateRoot, withIntermediateDirectories: true)
        NSWorkspace.shared.open(stateRoot)
    }

    @objc private func sendTestNotification() {
        sendGeneralNotification(
            title: "Codex Control Bar is ready",
            body: "Notifications and the application icon are configured correctly.",
            identifier: "codex-control-bar-menu-test-\(Int(Date().timeIntervalSince1970))"
        )
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

@main
private enum CodexControlBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = ControlBarController()
        app.delegate = delegate
        app.run()
    }
}
