// generate_icon.swift — renders Switchback's app icon + menu-bar template glyph.
//
// One source of truth for the mark: a forking "Y" track (silver, arrowheads at
// the two upper tips, a node on the stem) on Crossbar's blue gradient squircle.
// Geometry matches Crossbar's icon (8.5% margin, ~19.6% corner radius) so the
// sibling apps sit identically in Finder/Dock.
//
//   swift scripts/generate_icon.swift
//
import AppKit

// MARK: - Design constants (normalized to the squircle, top-left origin)

let MARGIN_FRAC: CGFloat = 87.0 / 1024.0     // Crossbar: 8.5% transparent margin
let CORNER_FRAC: CGFloat = 0.1965            // corner radius / squircle side
let STROKE_FRAC: CGFloat = 30.0 / 360.0      // Y stroke width / squircle side
let NODE_FRAC:   CGFloat = 24.0 / 360.0      // stem node radius / squircle side

// Glyph points in squircle-normalized [0,1] coords (from the approved SVG).
let FORK   = CGPoint(x: 0.500, y: 0.561)
let SHAFT_L = CGPoint(x: 0.358, y: 0.367)    // upper-left shaft end (arrowhead base)
let SHAFT_R = CGPoint(x: 0.642, y: 0.367)
let APEX_L  = CGPoint(x: 0.272, y: 0.250)    // arrowhead tips
let APEX_R  = CGPoint(x: 0.728, y: 0.250)
let TRIL_1  = CGPoint(x: 0.419, y: 0.322)
let TRIL_2  = CGPoint(x: 0.297, y: 0.411)
let TRIR_1  = CGPoint(x: 0.581, y: 0.322)
let TRIR_2  = CGPoint(x: 0.703, y: 0.411)
let NODE    = CGPoint(x: 0.500, y: 0.806)
let SILVER_Y0: CGFloat = 0.222               // silver gradient vertical span
let SILVER_Y1: CGFloat = 0.883

let GLYPH_MINX: CGFloat = 0.272, GLYPH_MAXX: CGFloat = 0.728
let GLYPH_MINY: CGFloat = 0.250, GLYPH_MAXY: CGFloat = 0.873  // node bottom

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}
let BLUE = [rgb(0x54,0xB0,0xFC), rgb(0x3D,0x98,0xF0), rgb(0x16,0x7A,0xDC)]
let SILVER = [rgb(0xF7,0xF9,0xFB), rgb(0xDC,0xE2,0xE8), rgb(0xC2,0xCA,0xD2)]

let space = CGColorSpaceCreateDeviceRGB()

func context(_ size: Int) -> CGContext {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                      bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(size)); c.scaleBy(x: 1, y: -1)  // → top-left origin
    c.setLineCap(.round); c.setLineJoin(.round)
    c.interpolationQuality = .high
    return c
}

func writePNG(_ ctx: CGContext, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// The glyph as a list of independent component paths (3 stroked segments, 2
// arrowheads, 1 node). Kept separate on purpose: overlapping subpaths with
// opposing winding would cancel and punch holes if unioned into one path, so
// each component is clipped/filled on its own and simply over-paints the rest.
func glyphComponents(map: (CGPoint) -> CGPoint, stroke: CGFloat, node: CGFloat) -> [CGPath] {
    var parts: [CGPath] = []
    for (a, b) in [(FORK, SHAFT_L), (FORK, SHAFT_R), (FORK, NODE)] {
        let line = CGMutablePath(); line.move(to: map(a)); line.addLine(to: map(b))
        parts.append(line.copy(strokingWithWidth: stroke, lineCap: .round,
                               lineJoin: .round, miterLimit: 10))
    }
    let triL = CGMutablePath(); triL.addLines(between: [map(APEX_L), map(TRIL_1), map(TRIL_2)]); triL.closeSubpath()
    let triR = CGMutablePath(); triR.addLines(between: [map(APEX_R), map(TRIR_1), map(TRIR_2)]); triR.closeSubpath()
    parts.append(triL); parts.append(triR)
    let n = map(NODE)
    let dot = CGMutablePath(); dot.addEllipse(in: CGRect(x: n.x - node, y: n.y - node, width: 2*node, height: 2*node))
    parts.append(dot)
    return parts
}

func drawGradient(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat],
                  from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// MARK: - App icon (colored squircle)

func renderAppIcon(_ size: Int, _ path: String) {
    let ctx = context(size)
    let S = CGFloat(size)
    let m = S * MARGIN_FRAC
    let side = S - 2*m
    let radius = side * CORNER_FRAC
    let square = CGRect(x: m, y: m, width: side, height: side)
    let squircle = CGPath(roundedRect: square, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    drawGradient(ctx, BLUE, [0, 0.5, 1], from: CGPoint(x: m, y: m), to: CGPoint(x: m, y: m+side))
    // Subtle top sheen.
    drawGradient(ctx, [rgb(255,255,255,0.22), rgb(255,255,255,0)], [0, 1],
                 from: CGPoint(x: m, y: m), to: CGPoint(x: m, y: m + side*0.53))
    ctx.restoreGState()

    func map(_ p: CGPoint) -> CGPoint { CGPoint(x: m + p.x*side, y: m + p.y*side) }
    for part in glyphComponents(map: map, stroke: side*STROKE_FRAC, node: side*NODE_FRAC) {
        ctx.saveGState()
        ctx.addPath(part); ctx.clip()
        drawGradient(ctx, SILVER, [0, 0.55, 1],
                     from: CGPoint(x: m, y: m + side*SILVER_Y0), to: CGPoint(x: m, y: m + side*SILVER_Y1))
        ctx.restoreGState()
    }
    writePNG(ctx, path)
}

// MARK: - Menu-bar template (monochrome glyph, fills the canvas)

func renderMenuBar(_ size: Int, _ path: String) {
    let ctx = context(size)
    let P = CGFloat(size)
    let pad = P * 0.06
    let glyphH = (GLYPH_MAXY - GLYPH_MINY)   // normalized glyph height in squircle units
    let scale = (P - 2*pad) / glyphH
    let glyphW = (GLYPH_MAXX - GLYPH_MINX) * scale
    let xOff = (P - glyphW) / 2
    func map(_ p: CGPoint) -> CGPoint {
        CGPoint(x: xOff + (p.x - GLYPH_MINX)*scale, y: pad + (p.y - GLYPH_MINY)*scale)
    }
    ctx.setFillColor(rgb(0, 0, 0))          // template — system recolors for light/dark
    for part in glyphComponents(map: map, stroke: scale*STROKE_FRAC, node: scale*NODE_FRAC) {
        ctx.addPath(part); ctx.fillPath(using: .winding)   // each filled alone → clean union
    }
    writePNG(ctx, path)
}

// MARK: - Emit assets

let base = FileManager.default.currentDirectoryPath
let appIconDir = "\(base)/Switchback/Assets.xcassets/AppIcon.appiconset"
let menuDir = "\(base)/Switchback/Assets.xcassets/MenuBarIcon.imageset"
try? FileManager.default.createDirectory(atPath: menuDir, withIntermediateDirectories: true)

for (name, px) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),
                   ("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),
                   ("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    renderAppIcon(px, "\(appIconDir)/\(name).png")
}
renderMenuBar(18, "\(menuDir)/menubar.png")
renderMenuBar(36, "\(menuDir)/menubar@2x.png")
renderMenuBar(54, "\(menuDir)/menubar@3x.png")
print("Icons generated.")
