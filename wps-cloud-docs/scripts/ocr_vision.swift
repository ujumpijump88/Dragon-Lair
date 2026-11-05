// macOS Swift + Vision 框架截图 OCR（中文/英文）
// 用途：vision_analyze 工具不可用时，读取截图中的文字（本机实测稳定，支持 zh-Hans）
// 用法：swift ocr_vision.swift /path/to/image.png
// 依赖：仅需系统自带 swift + Vision + ImageIO，零安装
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
    // sort top-to-bottom, then left-to-right
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
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cg, options: [:])
try handler.perform([request])
