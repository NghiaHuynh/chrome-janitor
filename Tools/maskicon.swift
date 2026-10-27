import AppKit
import CoreGraphics
import ImageIO

// Wraps full-bleed square artwork in the macOS icon grid: 1024 canvas,
// 824pt squircle inset 100pt, corner radius 183pt, transparent surround.
let args = CommandLine.arguments
guard args.count >= 3, let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write("usage: maskicon <in.png> <out.png>\n".data(using: .utf8)!)
    exit(1)
}

let side = 1024, inset: CGFloat = 100, radius: CGFloat = 183
guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { exit(1) }

let rect = CGRect(x: inset, y: inset, width: CGFloat(side) - inset * 2, height: CGFloat(side) - inset * 2)
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
ctx.draw(cg, in: rect)
guard let out = ctx.makeImage() else { exit(1) }

let url = URL(fileURLWithPath: args[2]) as CFURL
guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
