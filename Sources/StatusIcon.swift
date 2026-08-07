import AppKit

enum ControlBarIconStyle: String, CaseIterable {
    case gptKnot
    case codexSpark
    case pixelPet

    var title: String {
        switch self {
        case .gptKnot: return "GPT Knot"
        case .codexSpark: return "Codex Spark"
        case .pixelPet: return "Pixel Pet"
        }
    }
}

enum ControlBarIconState: Hashable {
    case idle
    case thinking
    case tool
    case permission
}

/// A compact six-loop GPT knot rendered directly into the menu bar. The mark
/// stays Codex blue at rest and uses motion/colour to communicate live state.
enum StatusIconRenderer {
    private static let frameCount = 40
    private static var cache: [String: NSImage] = [:]

    private static let codexBlue = NSColor(calibratedRed: 0.00, green: 0.32, blue: 0.72, alpha: 1)
    private static let electricBlue = NSColor(calibratedRed: 0.00, green: 0.62, blue: 1.00, alpha: 1)
    private static let cyan = NSColor(calibratedRed: 0.15, green: 0.91, blue: 1.00, alpha: 1)
    private static let violet = NSColor(calibratedRed: 0.43, green: 0.38, blue: 1.00, alpha: 1)
    private static let coral = NSColor(calibratedRed: 1.00, green: 0.31, blue: 0.28, alpha: 1)
    private static let amber = NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.12, alpha: 1)

    static func image(
        state: ControlBarIconState, phase: CGFloat, style: ControlBarIconStyle = .gptKnot
    ) -> NSImage {
        let frame = state == .idle ? 0 : Int((phase * CGFloat(frameCount)).rounded(.down)) % frameCount
        let key = "\(style.rawValue)-\(state)-\(frame)"
        if let image = cache[key] { return image }
        let made = render(state: state, phase: CGFloat(frame) / CGFloat(frameCount), style: style)
        cache[key] = made
        return made
    }

    static func accentColor(for state: ControlBarIconState) -> NSColor {
        switch state {
        case .idle: return codexBlue
        case .thinking: return electricBlue
        case .tool: return violet
        case .permission: return amber
        }
    }

    static func appIcon(pixelSize: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize), flipped: false) { rect in
            let radius = pixelSize * 0.225
            let background = NSBezierPath(roundedRect: rect.insetBy(dx: pixelSize * 0.035, dy: pixelSize * 0.035),
                                          xRadius: radius, yRadius: radius)
            NSGradient(colors: [
                NSColor(calibratedRed: 0.78, green: 0.95, blue: 1.00, alpha: 1),
                NSColor(calibratedRed: 0.38, green: 0.77, blue: 1.00, alpha: 1),
            ])?.draw(in: background, angle: -55)

            NSColor.white.withAlphaComponent(0.20).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: pixelSize * 0.15, dy: pixelSize * 0.15)).fill()
            let mark = StatusIconRenderer.image(state: .idle, phase: 0)
            mark.draw(in: NSRect(x: pixelSize * 0.13, y: pixelSize * 0.20,
                                 width: pixelSize * 0.74, height: pixelSize * 0.60),
                      from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func render(
        state: ControlBarIconState, phase: CGFloat, style: ControlBarIconStyle
    ) -> NSImage {
        let size = NSSize(width: 29, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current else { return false }
            context.cgContext.clear(rect)
            switch style {
            case .gptKnot:
                drawGPTKnot(in: rect, state: state, phase: phase)
            case .codexSpark:
                drawSpark(in: rect, state: state, phase: phase)
            case .pixelPet:
                drawPixelPet(in: rect, state: state, phase: phase)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription(for: state)
        return image
    }

    private static func drawGPTKnot(in rect: NSRect, state: ControlBarIconState, phase: CGFloat) {
        NSGraphicsContext.current?.saveGraphicsState()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let motion = motionParameters(state: state, phase: phase)
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: motion.rotation)
        transform.scale(by: motion.scale * 1.23)
        transform.translateX(by: -center.x, yBy: -center.y)
        transform.concat()

        drawActivityRays(center: center, state: state, phase: phase)
        for arm in 0..<6 {
            let wave = (sin(phase * .pi * 2 - CGFloat(arm) * .pi / 3) + 1) / 2
            drawArm(center: center, rotation: CGFloat(arm) * 60,
                    color: armColor(state: state, arm: arm, wave: wave),
                    width: 1.65 + motion.strokePulse * wave)
        }
        NSColor(calibratedWhite: 0.06, alpha: state == .idle ? 0.24 : 0.16).setStroke()
        let aperture = NSBezierPath(ovalIn: NSRect(x: center.x - 1.15, y: center.y - 1.15,
                                                   width: 2.3, height: 2.3))
        aperture.lineWidth = 0.45
        aperture.stroke()
        if state == .permission {
            amber.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 0.85, y: center.y - 0.85,
                                        width: 1.7, height: 1.7)).fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private static func drawSpark(in rect: NSRect, state: ControlBarIconState, phase: CGFloat) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let color = accentColor(for: state)
        let count = 12
        let rotation = state == .idle ? CGFloat.zero : phase * .pi * 2
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2 + rotation
            let wave = state == .idle ? CGFloat(index.isMultiple(of: 3) ? 1 : 0.55)
                : (sin(phase * .pi * 2 - CGFloat(index) * 0.62) + 1) / 2
            let inner: CGFloat = 2.7
            let outer: CGFloat = 7.0 + 2.1 * wave
            let ray = NSBezierPath()
            ray.move(to: NSPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            ray.line(to: NSPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            ray.lineCapStyle = .round
            ray.lineWidth = 1.05 + 0.65 * wave
            blend(color, state == .permission ? coral : cyan, fraction: wave * 0.65)
                .withAlphaComponent(0.55 + 0.45 * wave).setStroke()
            ray.stroke()
        }
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 1.45, y: center.y - 1.45,
                                    width: 2.9, height: 2.9)).fill()
    }

    private static func drawPixelPet(in rect: NSRect, state: ControlBarIconState, phase: CGFloat) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let color = accentColor(for: state)
        let unit: CGFloat = 1.75
        let origin = NSPoint(x: center.x - 4 * unit, y: center.y - 2 * unit)
        func pixel(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat = 1, _ height: CGFloat = 1,
                   _ fill: NSColor = color) {
            fill.setFill()
            NSBezierPath(rect: NSRect(x: origin.x + x * unit, y: origin.y + y * unit,
                                      width: width * unit + 0.15, height: height * unit + 0.15)).fill()
        }

        // Original blue pixel pet: compact body, expressive eyes, animated feet.
        pixel(1, 1, 6, 4)
        pixel(2, 5, 4, 1)
        pixel(0, 2, 1, 2)
        pixel(7, 2, 1, 2)
        let dark = NSColor(calibratedWhite: 0.05, alpha: 0.92)
        pixel(2, 4, 1, 1, dark)
        pixel(5, 4, 1, 1, dark)

        let step = state == .idle ? 0 : Int(phase * 4) % 2
        pixel(1, step == 0 ? -1 : 0, 1, 2)
        pixel(3, step == 0 ? 0 : -1, 1, 2)
        pixel(5, step == 0 ? -1 : 0, 1, 2)
        pixel(7, step == 0 ? 0 : -1, 1, 2)
        if state == .permission {
            pixel(3.5, 2.1, 1, 1, amber)
        } else if state == .tool {
            pixel(3.5, 2.0, 1, 1, violet)
        }
    }

    private static func drawArm(center: NSPoint, rotation: CGFloat, color: NSColor, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x - 0.7, y: center.y - 1.0))
        path.line(to: NSPoint(x: center.x - 0.7, y: center.y - 4.05))
        path.curve(to: NSPoint(x: center.x + 1.75, y: center.y - 5.45),
                   controlPoint1: NSPoint(x: center.x - 0.7, y: center.y - 5.0),
                   controlPoint2: NSPoint(x: center.x + 0.7, y: center.y - 5.75))
        path.line(to: NSPoint(x: center.x + 4.25, y: center.y - 4.0))
        path.curve(to: NSPoint(x: center.x + 4.25, y: center.y - 1.45),
                   controlPoint1: NSPoint(x: center.x + 5.05, y: center.y - 3.55),
                   controlPoint2: NSPoint(x: center.x + 5.05, y: center.y - 1.9))
        path.line(to: NSPoint(x: center.x + 1.65, y: center.y + 0.05))
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let rotationTransform = NSAffineTransform()
        rotationTransform.translateX(by: center.x, yBy: center.y)
        rotationTransform.rotate(byDegrees: rotation)
        rotationTransform.translateX(by: -center.x, yBy: -center.y)
        path.transform(using: rotationTransform as AffineTransform)

        NSColor(calibratedWhite: 0.01, alpha: 0.62).setStroke()
        path.lineWidth = width + 0.78
        path.stroke()
        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(0.52)
        shadow.shadowBlurRadius = 1.25
        shadow.shadowOffset = .zero
        shadow.set()
        color.setStroke()
        path.lineWidth = width
        path.stroke()
    }

    private static func armColor(state: ControlBarIconState, arm: Int, wave: CGFloat) -> NSColor {
        switch state {
        case .idle:
            return codexBlue
        case .thinking:
            return blend(codexBlue, electricBlue, fraction: wave).withAlphaComponent(0.82 + 0.18 * wave)
        case .tool:
            return blend(codexBlue, violet, fraction: wave).withAlphaComponent(0.84 + 0.16 * wave)
        case .permission:
            return blend(amber, coral, fraction: arm.isMultiple(of: 2) ? wave : 1 - wave)
        }
    }

    private static func drawActivityRays(center: NSPoint, state: ControlBarIconState, phase: CGFloat) {
        switch state {
        case .idle:
            return
        case .thinking:
            for index in 0..<10 {
                let angle = CGFloat(index) / 10 * .pi * 2 - .pi / 2
                let wave = (sin(phase * .pi * 2 - CGFloat(index) * 0.72) + 1) / 2
                let inner: CGFloat = 7.15
                let outer: CGFloat = 7.85 + 1.0 * wave
                let ray = NSBezierPath()
                ray.move(to: NSPoint(x: center.x + cos(angle) * inner,
                                     y: center.y + sin(angle) * inner))
                ray.line(to: NSPoint(x: center.x + cos(angle) * outer,
                                     y: center.y + sin(angle) * outer))
                ray.lineCapStyle = .round
                ray.lineWidth = 0.75 + 0.48 * wave
                blend(codexBlue, cyan, fraction: wave).withAlphaComponent(0.38 + 0.62 * wave).setStroke()
                ray.stroke()
            }
        case .tool:
            for index in 0..<6 {
                let angle = CGFloat(index) / 6 * .pi * 2 + phase * .pi * 2
                let wave = (sin(phase * .pi * 4 + CGFloat(index)) + 1) / 2
                let radius: CGFloat = 8.0
                let side: CGFloat = 0.8 + 0.7 * wave
                let point = NSPoint(x: center.x + cos(angle) * radius,
                                    y: center.y + sin(angle) * radius)
                blend(codexBlue, violet, fraction: wave).setFill()
                NSBezierPath(roundedRect: NSRect(x: point.x - side / 2, y: point.y - side / 2,
                                                 width: side, height: side),
                             xRadius: 0.35, yRadius: 0.35).fill()
            }
        case .permission:
            for index in 0..<3 {
                let arc = NSBezierPath()
                let start = CGFloat(index) * 120 + phase * 120
                arc.appendArc(withCenter: center, radius: 7.9,
                              startAngle: start, endAngle: start + 52)
                arc.lineWidth = 1.05
                (index == 0 ? coral : amber).setStroke()
                arc.stroke()
            }
        }
    }

    private static func blend(_ first: NSColor, _ second: NSColor, fraction: CGFloat) -> NSColor {
        first.blended(withFraction: max(0, min(1, fraction)), of: second) ?? first
    }

    private static func motionParameters(state: ControlBarIconState, phase: CGFloat)
        -> (rotation: CGFloat, scale: CGFloat, haloAlpha: CGFloat, strokePulse: CGFloat) {
        switch state {
        case .idle:
            return (0, 1, 0, 0)
        case .thinking:
            return (2.2 * sin(phase * .pi * 2), 0.97 + 0.035 * sin(phase * .pi * 2), 0.07, 0.26)
        case .tool:
            return (phase * 60, 0.98 + 0.025 * sin(phase * .pi * 4), 0.08, 0.20)
        case .permission:
            return (-2.5 * sin(phase * .pi * 2), 0.93 + 0.08 * (sin(phase * .pi * 2) + 1) / 2, 0.12, 0.18)
        }
    }

    private static func accessibilityDescription(for state: ControlBarIconState) -> String {
        switch state {
        case .idle: return "Codex idle"
        case .thinking: return "Codex thinking"
        case .tool: return "Codex using a tool"
        case .permission: return "Codex needs permission"
        }
    }
}
