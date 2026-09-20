import Foundation
import AppKit

// Generates Peek's app icon: a crimson squircle with three fanned white
// "window" cards, the front one lifted and glowing. Brand crimson #D13A63.
// usage: swift genicon.swift <out.png>
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let S: CGFloat = 1024

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError() }

// CG origin is bottom-left; we think top-left, so flip Y.
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

// --- Background squircle with a diagonal crimson gradient ---
let inset: CGFloat = 88
let bg = roundedRect(inset, inset, S - 2*inset, S - 2*inset, 232)
ctx.saveGState()
ctx.addPath(bg); ctx.clip()
let grad = CGGradient(colorsSpace: cs,
    colors: [rgb(0xE0, 0x6A, 0x8D), rgb(0xD1, 0x3A, 0x63), rgb(0xA6, 0x25, 0x4B)] as CFArray,
    locations: [0.0, 0.5, 1.0])!
ctx.drawLinearGradient(grad, start: CGPoint(x: inset, y: inset), end: CGPoint(x: S - inset, y: S - inset),
                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// very soft, contained top sheen (stays away from the corners)
let sheen = CGGradient(colorsSpace: cs,
    colors: [rgb(255,255,255,0.10), rgb(255,255,255,0.0)] as CFArray, locations: [0.0, 1.0])!
ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: 512, y: 300), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 300), endRadius: 430, options: [])
ctx.restoreGState()

// --- Three fanned white cards (back → front), each with a soft shadow ---
// Front card anchored lower-right; each card behind is offset up-left.
let cardW: CGFloat = 372, cardH: CGFloat = 300, radius: CGFloat = 30
let frontX: CGFloat = 430, frontY: CGFloat = 398
let dx: CGFloat = 78, dy: CGFloat = 74

func drawCard(_ x: CGFloat, _ y: CGFloat, glow: Bool) {
    if glow {
        // bright crimson halo behind the front card
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 70, color: rgb(0xFF, 0x5A, 0x86, 0.95))
        ctx.addPath(roundedRect(x, y, cardW, cardH, radius))
        ctx.setFillColor(rgb(0xFF, 0x5A, 0x86)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 26, color: rgb(0x5A, 0x08, 0x1E, 0.34))
    let path = roundedRect(x, y, cardW, cardH, radius)
    ctx.addPath(path); ctx.clip()
    // vertical white gradient for a subtle sheen
    let cardGrad = CGGradient(colorsSpace: cs,
        colors: [rgb(255,255,255), rgb(0xEC, 0xEE, 0xF4)] as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(cardGrad, start: CGPoint(x: x, y: y),
                           end: CGPoint(x: x, y: y + cardH), options: [])
    ctx.restoreGState()
}

drawCard(frontX - 2*dx, frontY - 2*dy, glow: false)  // back
drawCard(frontX - dx,   frontY - dy,   glow: false)  // middle
drawCard(frontX,        frontY,        glow: true)   // front (glowing)

guard let cg = ctx.makeImage() else { fatalError("image fail") }
let rep = NSBitmapImageRep(cgImage: cg)
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.lastPathComponent)")
