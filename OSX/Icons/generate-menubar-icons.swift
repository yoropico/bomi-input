import AppKit

// Render one icon at `size`px as a black+alpha template:
// opaque black cloud (SF Symbol "cloud.fill" silhouette) with the label knocked out to alpha 0.
func renderIcon(size: Int, label: String?) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.shouldAntialias = true

    // Cloud silhouette from SF Symbol cloud.fill, aspect-fit to fill the tile width.
    let cfg = NSImage.SymbolConfiguration(pointSize: s, weight: .black)
    let sym = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(cfg)!
    let isz = sym.size
    let scale = min(s / isz.width, s / isz.height)
    let w = isz.width * scale, h = isz.height * scale
    sym.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
    // Normalize antialiased symbol pixels to an opaque black silhouette (alpha preserved).
    ctx.compositingOperation = .sourceAtop
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()
    ctx.compositingOperation = .sourceOver

    if let label = label, !label.isEmpty {
        ctx.compositingOperation = .destinationOut   // erase label region -> alpha 0
        let fs = s * (label.count >= 2 ? 0.40 : 0.52)
        let font = NSFont.systemFont(ofSize: fs, weight: .heavy)
        let str = NSAttributedString(string: label,
            attributes: [.font: font, .foregroundColor: NSColor.black])
        let sz = str.size()
        str.draw(at: NSPoint(x: s / 2 - sz.width / 2, y: s / 2 - sz.height / 2 - s * 0.04))
        ctx.compositingOperation = .sourceOver
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func alphaStats(_ rep: NSBitmapImageRep) -> (opaque: Int, transparent: Int) {
    var opaque = 0, transparent = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            let a = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
            if a > 0.5 { opaque += 1 } else { transparent += 1 }
        }
    }
    return (opaque, transparent)
}

// arg 1 (optional): path to Assets.xcassets (default assumes run from repo root)
let assetsDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "OSX/Assets.xcassets"

let icons: [(String, String?)] = [
    ("eng", nil), ("han", "안"), ("han2", "2"), ("han3", "3"),
    ("han390", "9"), ("han3final", "F"), ("hanroman", "R"), ("qwerty", "Q"),
]

for (name, label) in icons {
    for (suffix, size) in [("", 16), ("@2x", 32)] {
        let rep = renderIcon(size: size, label: label)
        guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png fail") }
        let path = "\(assetsDir)/\(name).imageset/\(name)\(suffix).png"
        try! data.write(to: URL(fileURLWithPath: path))
        let st = alphaStats(rep)
        print("wrote \(path)  opaque=\(st.opaque) transparent=\(st.transparent)")
    }
}
print("done: \(icons.count) imagesets x 2 scales = \(icons.count * 2) png")
