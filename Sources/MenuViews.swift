import AppKit

enum ControlBarPalette {
    static let width: CGFloat = 410

    static func status(_ state: String) -> NSColor {
        switch state {
        case "permission": return .systemOrange
        case "thinking": return .systemBlue
        case "tool": return .systemPurple
        case "done": return .systemGreen
        default: return .secondaryLabelColor
        }
    }

    static func meter(_ percent: Int) -> NSColor {
        switch percent {
        case 90...: return .systemRed
        case 75...: return .systemOrange
        default: return .controlAccentColor
        }
    }
}

final class SectionHeaderView: NSView {
    init(title: String, symbol: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: ControlBarPalette.width, height: 31))

        let icon = NSImageView(frame: NSRect(x: 14, y: 8, width: 15, height: 15))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .tertiaryLabelColor
        addSubview(icon)

        let label = NSTextField(labelWithString: title.uppercased())
        label.frame = NSRect(x: 36, y: 7, width: 350, height: 17)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.attributedStringValue = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 0.8,
            ]
        )
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

class HoverMenuRow: NSView {
    var onClick: (() -> Void)?
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.16).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        guard onClick != nil else { return }
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.28).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.16).cgColor
        onClick?()
    }
}

struct SessionRowModel {
    let title: String
    let state: String
    let subtitle: String
    let timer: String?
    let contextPercent: Int?
    let surface: String?
    let tooltip: String
}

final class SessionMenuRow: HoverMenuRow {
    init(model: SessionRowModel, onClick: @escaping () -> Void) {
        super.init(frame: NSRect(x: 5, y: 0, width: ControlBarPalette.width - 10, height: 78))
        self.onClick = onClick
        toolTip = model.tooltip

        let statusColor = ControlBarPalette.status(model.state)
        let dot = NSView(frame: NSRect(x: 13, y: 55, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = statusColor.cgColor
        dot.layer?.shadowColor = statusColor.cgColor
        dot.layer?.shadowOpacity = model.state == "thinking" || model.state == "tool" ? 0.55 : 0
        dot.layer?.shadowRadius = 4
        dot.layer?.shadowOffset = .zero
        addSubview(dot)

        let title = NSTextField(labelWithString: model.title)
        let hasSurface = !(model.surface ?? "").isEmpty
        let titleRight: CGFloat = model.timer == nil ? (hasSurface ? 335 : 383) : (hasSurface ? 255 : 298)
        title.frame = NSRect(x: 34, y: 50, width: titleRight - 34, height: 21)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingMiddle
        addSubview(title)

        if let surface = model.surface, !surface.isEmpty {
            let surfaceField = NSTextField(labelWithString: surface.uppercased())
            let x: CGFloat = model.timer == nil ? 343 : 263
            surfaceField.frame = NSRect(x: x, y: 51, width: 40, height: 18)
            surfaceField.alignment = .center
            surfaceField.font = .systemFont(ofSize: 8.5, weight: .bold)
            surfaceField.textColor = .secondaryLabelColor
            surfaceField.wantsLayer = true
            surfaceField.layer?.cornerRadius = 6
            surfaceField.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
            addSubview(surfaceField)
        }

        if let timer = model.timer {
            let timerField = NSTextField(labelWithString: "Turn  ·  \(timer)")
            timerField.frame = NSRect(x: 302, y: 51, width: 81, height: 19)
            timerField.alignment = .right
            timerField.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
            timerField.textColor = .secondaryLabelColor
            addSubview(timerField)
        }

        let subtitle = NSTextField(labelWithString: model.subtitle)
        subtitle.frame = NSRect(x: 34, y: 29, width: 349, height: 18)
        subtitle.font = .systemFont(ofSize: 11.5, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        addSubview(subtitle)

        if let percent = model.contextPercent {
            let value = max(0, min(100, percent))
            let color = ControlBarPalette.meter(value)

            let contextLabel = NSTextField(labelWithString: "Context window")
            contextLabel.frame = NSRect(x: 34, y: 7, width: 86, height: 17)
            contextLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
            contextLabel.textColor = .secondaryLabelColor
            addSubview(contextLabel)

            let track = NSView(frame: NSRect(x: 126, y: 13, width: 190, height: 5))
            track.wantsLayer = true
            track.layer?.cornerRadius = 2.5
            track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
            let fill = CALayer()
            fill.frame = CGRect(x: 0, y: 0, width: 190 * CGFloat(value) / 100, height: 5)
            fill.cornerRadius = 2.5
            fill.backgroundColor = color.cgColor
            track.layer?.addSublayer(fill)
            addSubview(track)

            let context = NSTextField(labelWithString: "\(value)% used")
            context.frame = NSRect(x: 324, y: 6, width: 59, height: 18)
            context.alignment = .right
            context.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            context.textColor = color
            addSubview(context)
        } else {
            let context = NSTextField(labelWithString: "Context window  ·  waiting for usage data")
            context.frame = NSRect(x: 34, y: 7, width: 349, height: 17)
            context.font = .systemFont(ofSize: 10.5, weight: .medium)
            context.textColor = .secondaryLabelColor
            addSubview(context)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class LimitMenuRow: NSView {
    init(title: String, percent: Int, reset: String?) {
        super.init(frame: NSRect(x: 0, y: 0, width: ControlBarPalette.width, height: 54))
        let value = max(0, min(100, percent))
        let color = ControlBarPalette.meter(value)

        let titleField = NSTextField(labelWithString: title)
        titleField.frame = NSRect(x: 14, y: 31, width: 188, height: 18)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleField.textColor = .labelColor
        addSubview(titleField)

        if let reset {
            let resetField = NSTextField(labelWithString: reset)
            resetField.frame = NSRect(x: 205, y: 31, width: 111, height: 18)
            resetField.alignment = .right
            resetField.font = .systemFont(ofSize: 11.5)
            resetField.textColor = .secondaryLabelColor
            resetField.lineBreakMode = .byTruncatingTail
            addSubview(resetField)
        }

        let percentField = NSTextField(labelWithString: "\(value)% used")
        percentField.frame = NSRect(x: 326, y: 30, width: 68, height: 19)
        percentField.alignment = .right
        percentField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percentField.textColor = color
        addSubview(percentField)

        let track = NSView(frame: NSRect(x: 14, y: 12, width: 380, height: 6))
        track.wantsLayer = true
        track.layer?.cornerRadius = 3
        track.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        let fill = CALayer()
        fill.frame = CGRect(x: 0, y: 0, width: 380 * CGFloat(value) / 100, height: 6)
        fill.cornerRadius = 3
        fill.backgroundColor = color.cgColor
        track.layer?.addSublayer(fill)
        addSubview(track)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class MCPMenuRow: HoverMenuRow {
    init(name: String, tools: Int, status: String, healthy: Bool, details: NSMenu) {
        super.init(frame: NSRect(x: 5, y: 0, width: ControlBarPalette.width - 10, height: 37))
        onClick = { [weak self] in
            guard let self, let event = NSApp.currentEvent else { return }
            NSMenu.popUpContextMenu(details, with: event, for: self)
        }

        let dot = NSView(frame: NSRect(x: 10, y: 14, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = (healthy ? NSColor.systemGreen : NSColor.systemOrange).cgColor
        addSubview(dot)

        let nameField = NSTextField(labelWithString: name)
        nameField.frame = NSRect(x: 28, y: 9, width: 184, height: 19)
        nameField.font = .systemFont(ofSize: 12.5, weight: .medium)
        nameField.textColor = .labelColor
        nameField.lineBreakMode = .byTruncatingMiddle
        addSubview(nameField)

        let statusField = NSTextField(labelWithString: status)
        statusField.frame = NSRect(x: 205, y: 9, width: 105, height: 19)
        statusField.alignment = .right
        statusField.font = .systemFont(ofSize: 11)
        statusField.textColor = .secondaryLabelColor
        addSubview(statusField)

        let badge = NSTextField(labelWithString: "\(tools) tool\(tools == 1 ? "" : "s")")
        badge.frame = NSRect(x: 316, y: 7, width: 61, height: 21)
        badge.alignment = .center
        badge.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        badge.textColor = .secondaryLabelColor
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 7
        badge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        addSubview(badge)

        let chevron = NSImageView(frame: NSRect(x: 383, y: 13, width: 7, height: 11))
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Show MCP tools")
        chevron.contentTintColor = .tertiaryLabelColor
        addSubview(chevron)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class StaticMenuRow: NSView {
    init(text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: ControlBarPalette.width, height: 29))
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 14, y: 5, width: 380, height: 19)
        label.font = .systemFont(ofSize: 12.5)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class MonitorStatusRow: NSView {
    init(title: String, detail: String, healthy: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: ControlBarPalette.width, height: 35))

        let color: NSColor = healthy ? .systemGreen : .systemOrange
        let dot = NSView(frame: NSRect(x: 15, y: 14, width: 7, height: 7))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = color.cgColor
        addSubview(dot)

        let titleField = NSTextField(labelWithString: title)
        titleField.frame = NSRect(x: 32, y: 8, width: 165, height: 19)
        titleField.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleField.textColor = .labelColor
        addSubview(titleField)

        let detailField = NSTextField(labelWithString: detail)
        detailField.frame = NSRect(x: 195, y: 8, width: 199, height: 19)
        detailField.alignment = .right
        detailField.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingHead
        addSubview(detailField)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
