import AppKit

precondition(StatusPresentation.thinkingWords.contains("Thinking"))
precondition(StatusPresentation.thinkingWords.contains("Struggling"))
for _ in 0..<20 {
    precondition(StatusPresentation.nextThinkingWord(previous: "Thinking") != "Thinking")
}
precondition(StatusPresentation.progressDots(second: 0) == ".")
precondition(StatusPresentation.progressDots(second: 1) == "..")
precondition(StatusPresentation.progressDots(second: 2) == "...")
precondition(StatusPresentation.progressDots(second: 3) == ".")
precondition(StatusPresentation.eventIsNewer(
    timestamp: "2026-08-12T15:03:16.622Z", thanUnix: 1_786_454_305
))
precondition(!StatusPresentation.eventIsNewer(
    timestamp: "2026-08-11T13:18:00.000Z", thanUnix: 1_786_454_305
))

func saturatedPixelCount(_ image: NSImage) -> Int {
    guard let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data) else { return 0 }
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                  color.alphaComponent > 0.12 else { continue }
            let channels = [color.redComponent, color.greenComponent, color.blueComponent]
            if (channels.max() ?? 0) - (channels.min() ?? 0) > 0.12 { count += 1 }
        }
    }
    return count
}

let states: [ControlBarIconState] = [.idle, .thinking, .tool, .permission]
for style in ControlBarIconStyle.allCases {
    for state in states {
        let image = StatusIconRenderer.image(state: state, phase: 0, style: style)
        precondition(image.size == NSSize(width: 29, height: 22))
        precondition(!image.isTemplate)
        precondition(saturatedPixelCount(image) >= 8, "\(style) \(state) is not visibly colourful")
    }
    for state in states.dropFirst() {
        let first = StatusIconRenderer.image(state: state, phase: 0, style: style).tiffRepresentation
        let later = StatusIconRenderer.image(state: state, phase: 0.35, style: style).tiffRepresentation
        precondition(first != later, "\(style) \(state) animation frame did not change")
    }
}

let applicationIcon = StatusIconRenderer.appIcon(pixelSize: 128)
precondition(applicationIcon.size == NSSize(width: 128, height: 128))
precondition(saturatedPixelCount(applicationIcon) > 500)

// Exercise every cached animation frame repeatedly; rendering must remain
// valid and bounded during long menu-bar runs.
for cycle in 0..<5 {
    for style in ControlBarIconStyle.allCases {
        for state in states {
            for frame in 0..<40 {
                let phase = CGFloat(frame) / 40 + CGFloat(cycle)
                let image = StatusIconRenderer.image(state: state, phase: phase, style: style)
                precondition(image.tiffRepresentation?.isEmpty == false)
            }
        }
    }
}

let preview = NSImage(size: NSSize(width: 650, height: 330), flipped: false) { rect in
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    NSBezierPath(rect: rect).fill()
    let names = ["Idle", "Thinking", "Tool", "Permission"]
    for (styleIndex, style) in ControlBarIconStyle.allCases.enumerated() {
        let y = CGFloat(230 - styleIndex * 105)
        style.title.draw(at: NSPoint(x: 12, y: y + 38), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.72),
        ])
        for (index, state) in states.enumerated() {
            let x = CGFloat(135 + index * 125)
            StatusIconRenderer.image(state: state, phase: 0.35, style: style).draw(
                in: NSRect(x: x, y: y, width: 92, height: 70), from: .zero,
                operation: .sourceOver, fraction: 1
            )
            names[index].draw(at: NSPoint(x: x + 20, y: y - 3), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.48),
            ])
        }
    }
    return true
}
if let data = preview.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: data),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "build/IconPreview.png"), options: .atomic)
}

print("Colour icon frames: OK")
