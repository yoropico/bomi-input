import AppKit

// Menu-bar IME indicator icons, monochrome template, NO inner text.
// Korean modes get a FILLED cloud (SF Symbol "cloud.fill"); English/roman modes get an
// OUTLINE cloud ("cloud"). The active mode's name is already shown beside the icon in the
// input menu / picker, so the menu bar only needs to convey Korean vs English at a glance.
// Rendered to static PNGs at generation time (no runtime SF Symbol dependency).

func makeSymbol(_ name: String, _ pointSize: CGFloat) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .black)
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(cfg)!
}

// Tight opaque bounds of a symbol as fractions of its intrinsic size (fy from the TOP).
func tightFractions(_ name: String) -> (fx: CGFloat, fy: CGFloat, fw: CGFloat, fh: CGFloat) {
    let sym = makeSymbol(name, 256)
    let isz = sym.size
    let W = Int(ceil(isz.width)), H = Int(ceil(isz.height))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    sym.draw(in: NSRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H)))
    NSGraphicsContext.restoreGraphicsState()
    var minX = W, minY = H, maxX = -1, maxY = -1
    for y in 0..<H {
        for x in 0..<W where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
    let bw = CGFloat(maxX - minX + 1), bh = CGFloat(maxY - minY + 1)
    return (CGFloat(minX) / CGFloat(W), CGFloat(minY) / CGFloat(H), bw / CGFloat(W), bh / CGFloat(H))
}

// Render `symbolName` as an opaque black template, tight bounds aspect-fit to the tile (no clip).
func renderIcon(symbolName: String, frac: (fx: CGFloat, fy: CGFloat, fw: CGFloat, fh: CGFloat),
                size: Int) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.shouldAntialias = true
    let margin: CGFloat = 0.0   // fill the tile fully (no clip); outline strokes must not be cut
    let target = s * (1 - 2 * margin)
    let sym = makeSymbol(symbolName, s)
    let isz = sym.size
    // aspect-fit the tight cloud bounds into the tile -> no clipping, natural cloud proportions
    let scale = min(target / (frac.fw * isz.width), target / (frac.fh * isz.height))
    let Dw = isz.width * scale, Dh = isz.height * scale
    let cx = (frac.fx + frac.fw / 2) * Dw
    let cyFromBottom = (1 - (frac.fy + frac.fh / 2)) * Dh
    sym.draw(in: NSRect(x: s / 2 - cx, y: s / 2 - cyFromBottom, width: Dw, height: Dh))
    // normalize antialiased symbol pixels to opaque black (alpha preserved -> template mask)
    ctx.compositingOperation = .sourceAtop
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()
    ctx.compositingOperation = .sourceOver
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func alphaStats(_ rep: NSBitmapImageRep) -> (opaque: Int, transparent: Int) {
    var opaque = 0, transparent = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
            opaque += 1
        }
    }
    transparent = rep.pixelsWide * rep.pixelsHigh - opaque
    return (opaque, transparent)
}

// arg 1 (optional): path to Assets.xcassets (default assumes run from repo root)
let assetsDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "OSX/Assets.xcassets"

// Korean (ko) -> filled cloud; English/roman (en) -> outline cloud. Classification per Info.plist
// TISIntendedLanguage.
let filled = "cloud.fill"
let outline = "cloud"
let icons: [(name: String, symbol: String)] = [
    ("eng", outline), ("qwerty", outline),
    ("han", filled), ("han2", filled), ("han3", filled),
    ("han390", filled), ("han3final", filled), ("hanroman", filled),
]

var fracCache: [String: (fx: CGFloat, fy: CGFloat, fw: CGFloat, fh: CGFloat)] = [:]
func frac(_ name: String) -> (fx: CGFloat, fy: CGFloat, fw: CGFloat, fh: CGFloat) {
    if let f = fracCache[name] { return f }
    let f = tightFractions(name); fracCache[name] = f; return f
}

for (name, symbol) in icons {
    for (suffix, size) in [("", 16), ("@2x", 32)] {
        let rep = renderIcon(symbolName: symbol, frac: frac(symbol), size: size)
        guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png fail") }
        let path = "\(assetsDir)/\(name).imageset/\(name)\(suffix).png"
        try! data.write(to: URL(fileURLWithPath: path))
        let st = alphaStats(rep)
        print("wrote \(path)  [\(symbol)]  opaque=\(st.opaque) transparent=\(st.transparent)")
    }
}
print("done: \(icons.count) imagesets x 2 scales = \(icons.count * 2) png")
