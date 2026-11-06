// Renders the Orbit app icon (the web app's cloud with an upload arrow) in the Todo/Shell icon style:
// swift design/render-icon.swift <out.png> [light|dark|tinted|splash]
import AppKit
import SwiftUI

extension Color {
    init(_ hex: UInt32, _ a: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: a)
    }
}

enum Variant: String { case light, dark, tinted, splash }

struct Cloud: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 640
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 0, y: 230 * s, width: 640 * s, height: 190 * s), cornerSize: CGSize(width: 95 * s, height: 95 * s))
        p.addEllipse(in: CGRect(x: 60 * s, y: 110 * s, width: 280 * s, height: 280 * s))
        p.addEllipse(in: CGRect(x: 200 * s, y: 0, width: 360 * s, height: 360 * s))
        p.addEllipse(in: CGRect(x: 400 * s, y: 160 * s, width: 240 * s, height: 240 * s))
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

struct Arrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.width / 2))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.width / 2))
        return p
    }
}

struct Icon: View {
    let variant: Variant

    private var glyph: AnyShapeStyle {
        switch variant {
        case .dark, .splash: AnyShapeStyle(LinearGradient(colors: [.white, Color(0xD8C8FF), Color(0x9270FF)], startPoint: .top, endPoint: .bottom))
        case .light: AnyShapeStyle(LinearGradient(colors: [Color(0x7C5CFF), Color(0x5B3FE0), Color(0x3B24A8)], startPoint: .top, endPoint: .bottom))
        case .tinted: AnyShapeStyle(Color.white)
        }
    }

    private var cutout: Color {
        switch variant {
        case .dark, .splash: Color(0x140E38)
        case .light: Color(0xF1EEFC)
        case .tinted: .black
        }
    }

    private var glow: Color {
        switch variant {
        case .dark, .splash: Color(0x9270FF, 0.95)
        case .light: Color(0x7C5CFF, 0.35)
        case .tinted: .clear
        }
    }

    var body: some View {
        ZStack {
            switch variant {
            case .dark, .splash:
                LinearGradient(colors: [Color(0x261A63), Color(0x110C30), Color(0x06051A)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(0x4B33B8, 0.7), .clear], center: UnitPoint(x: 0.28, y: 0.22), startRadius: 0, endRadius: 760)
            case .light:
                LinearGradient(colors: [Color(0xFFFFFF), Color(0xF1EEFC), Color(0xDCD4FA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(0xC4B5FD, 0.55), .clear], center: UnitPoint(x: 0.75, y: 0.85), startRadius: 0, endRadius: 700)
            case .tinted:
                Color.black
            }
            Cloud()
                .fill(glyph)
                .frame(width: 640, height: 420)
                .shadow(color: glow, radius: 34)
                .offset(y: 10)
            Arrow()
                .stroke(cutout, style: StrokeStyle(lineWidth: 58, lineCap: .round, lineJoin: .round))
                .frame(width: 190, height: 230)
                .offset(y: 70)
        }
        .frame(width: 1024, height: 1024)
        .clipped()
    }
}

let args = CommandLine.arguments
let variant = Variant(rawValue: args.count > 2 ? args[2] : "light") ?? .light
if variant == .splash {
    // The launch screen shows the icon as iOS would: rounded, on a transparent canvas.
    MainActor.assumeIsolated {
        let view = Icon(variant: .splash).clipShape(RoundedRectangle(cornerRadius: 1024 * 0.2237, style: .continuous))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        try! NSBitmapImageRep(cgImage: renderer.cgImage!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
    }
    exit(0)
}
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon(variant: variant))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    // App Store icons must be opaque; redraw without an alpha channel.
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
}
