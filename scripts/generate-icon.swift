#!/usr/bin/env swift
// Generates the NotchFlow macOS icon from editable SwiftUI shapes.
// Run from the repository root: swift scripts/generate-icon.swift

import AppKit
import SwiftUI

/// A continuous N suggests the movement between planning and focused work.
private struct FlowMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 30))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 54, y: rect.minY + 12),
            control: CGPoint(x: rect.minX, y: rect.minY - 24))
        path.addLine(to: CGPoint(x: rect.maxX - 54, y: rect.maxY - 12))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - 30),
            control: CGPoint(x: rect.maxX, y: rect.maxY + 24))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private struct Icon: View {
    private let outline = RoundedRectangle(cornerRadius: 185, style: .continuous)
    private let blue = Color(red: 0.20, green: 0.48, blue: 1.0)
    private let cyan = Color(red: 0.47, green: 0.87, blue: 1.0)

    var body: some View {
        ZStack {
            ZStack {
                outline.fill(LinearGradient(
                    colors: [Color(red: 0.16, green: 0.18, blue: 0.22),
                             Color(red: 0.055, green: 0.065, blue: 0.085)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))

                // A quiet pool of blue behind the monogram adds depth.
                Ellipse()
                    .fill(blue.opacity(0.20))
                    .frame(width: 560, height: 420)
                    .blur(radius: 90)
                    .offset(y: 150)

                // The inset silhouette echoes the Mac's physical notch.
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 42,
                    bottomTrailingRadius: 42, topTrailingRadius: 0)
                    .fill(Color(red: 0.025, green: 0.03, blue: 0.04))
                    .frame(width: 292, height: 94)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 94, height: 5)
                            .padding(.bottom, 17)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)

                FlowMark()
                    .stroke(blue.opacity(0.30), style: StrokeStyle(lineWidth: 96, lineCap: .round, lineJoin: .round))
                    .frame(width: 348, height: 320)
                    .blur(radius: 25)
                    .offset(y: 45)

                FlowMark()
                    .stroke(
                        LinearGradient(colors: [cyan, Color(red: 0.32, green: 0.67, blue: 1), blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 88, lineCap: .round, lineJoin: .round))
                    .frame(width: 348, height: 320)
                    .shadow(color: .black.opacity(0.32), radius: 12, y: 14)
                    .offset(y: 35)
            }
            .frame(width: 824, height: 824)
            .clipShape(outline)
            .overlay(outline.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.035), .white.opacity(0.09)],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3))
            .shadow(color: .black.opacity(0.32), radius: 20, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
private func render(size: Int, to url: URL) throws {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = CGFloat(size) / 1024
    guard let image = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("Unable to render the icon at \(size) pixels")
    }
    try data.write(to: url)
}

let folder = URL(fileURLWithPath: "NotchFlow/Assets.xcassets/AppIcon.appiconset")
let files: [(String, Int)] = [
    ("icon_16.png", 16), ("icon_32.png", 32), ("icon_32@2x.png", 64),
    ("icon_128.png", 128), ("icon_128@2x.png", 256), ("icon_256.png", 256),
    ("icon_256@2x.png", 512), ("icon_512.png", 512), ("icon_512@2x.png", 1024),
]
try MainActor.assumeIsolated {
    for (name, size) in files {
        try render(size: size, to: folder.appendingPathComponent(name))
    }
}
print("Wrote \(files.count) icons to \(folder.path)")
