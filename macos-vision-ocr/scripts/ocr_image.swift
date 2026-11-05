// macOS Vision OCR — zero-install text extraction from images.
// Usage: swift ocr_image.swift /path/to/image.png
// Requires /usr/bin/swift (Xcode Command Line Tools). Handles zh-Hans + en-US.
import Foundation
import Vision
import ImageIO

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path) as CFURL
guard let src = CGImageSourceCreateWithURL(url, nil),
      let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("ERROR: cannot load image")
    exit(1)
}

let request = VNRecognizeTextRequest { req, _ in
    guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
    // Sort top-to-bottom, then left-to-right. Vision uses bottom-left origin
    // with y-up coordinates — invert midY for reading order.
    let sorted = obs.sorted { a, b in
        let ay = a.boundingBox.midY, by = b.boundingBox.midY
        if abs(ay - by) > 0.02 { return ay > by }
        return a.boundingBox.minX < b.boundingBox.minX
    }
    for o in sorted {
        if let t = o.topCandidates(1).first {
            print(t.string)
        }
    }
}
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "en-US"]   // add "zh-Hant" for Traditional Chinese
request.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try handler.perform([request])
