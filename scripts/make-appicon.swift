// Rasterizează Resources/AppIcon.svg în toate dimensiunile cerute de macOS.
//
// De ce Swift și nu rsvg-convert/ImageMagick: niciunul nu e instalat pe
// acest Mac, iar o pictogramă nu merită o dependință Homebrew în plus.
// `NSImage` citește SVG nativ (`_NSSVGImageRep`) începând cu macOS 10.15 și
// îl redesenează VECTORIAL la fiecare dimensiune — nu scalează un PNG mare,
// deci muchiile rămân curate și la 16 px.
import AppKit

struct Slot {
    let size: Int       // dimensiunea logică (pt)
    let scale: Int      // 1 sau 2
    var pixels: Int { size * scale }
    var filename: String { "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png" }
}

let slots: [Slot] = [
    Slot(size: 16, scale: 1), Slot(size: 16, scale: 2),
    Slot(size: 32, scale: 1), Slot(size: 32, scale: 2),   // @2x = 64 px
    Slot(size: 128, scale: 1), Slot(size: 128, scale: 2),
    Slot(size: 256, scale: 1), Slot(size: 256, scale: 2),
    Slot(size: 512, scale: 1), Slot(size: 512, scale: 2)  // @2x = 1024 px
]

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("Utilizare: make-appicon.swift <sursa.svg> <folder.appiconset>\n".data(using: .utf8)!)
    exit(2)
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])

guard let image = NSImage(contentsOf: source) else {
    FileHandle.standardError.write("Nu am putut citi \(source.path)\n".data(using: .utf8)!)
    exit(1)
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for slot in slots {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: slot.pixels, pixelsHigh: slot.pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }

    // `size` în puncte = size în pixeli: desenăm 1:1, fără factor de scală
    // moștenit din ecranul curent (altfel un Mac Retina ar dubla tot).
    rep.size = NSSize(width: slot.pixels, height: slot.pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: slot.pixels, height: slot.pixels),
               from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try data.write(to: output.appendingPathComponent(slot.filename))
    print("  \(slot.filename) — \(slot.pixels)×\(slot.pixels)")
}

// Contents.json, generat din aceeași listă: o singură sursă de adevăr
// pentru dimensiuni, ca fișierul să nu ajungă niciodată desincronizat de
// PNG-urile de lângă el.
let images = slots.map { slot in
    """
        {
          "filename" : "\(slot.filename)",
          "idiom" : "mac",
          "scale" : "\(slot.scale)x",
          "size" : "\(slot.size)x\(slot.size)"
        }
    """
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "gdc",
    "version" : 1
  }
}

"""
try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("  Contents.json")
