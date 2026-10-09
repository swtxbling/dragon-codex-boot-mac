import Foundation
import CoreGraphics

struct ScreenFrame: Codable {
    var time: Double
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

func smoothProgress(_ value: Double) -> Double {
    let t = min(1, max(0, value))
    return t * t * (3 - 2 * t)
}

func mixRect(_ a: CGRect, _ b: CGRect, _ fraction: Double) -> CGRect {
    let t = CGFloat(min(1, max(0, fraction)))
    return CGRect(x: a.minX + (b.minX - a.minX) * t,
                  y: a.minY + (b.minY - a.minY) * t,
                  width: a.width + (b.width - a.width) * t,
                  height: a.height + (b.height - a.height) * t)
}

func aspectFitRect(content: CGSize, in bounds: CGRect) -> CGRect {
    guard content.width > 0, content.height > 0 else { return bounds }
    let scale = min(bounds.width / content.width, bounds.height / content.height)
    let size = CGSize(width: content.width * scale, height: content.height * scale)
    return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                  width: size.width, height: size.height)
}

func screenRect(frames: [ScreenFrame], time: Double) -> CGRect {
    guard let first = frames.first, let last = frames.last else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
    if time <= first.time { return first.rect }
    for i in 1..<frames.count where time <= frames[i].time {
        let a = frames[i - 1], b = frames[i]
        return mixRect(a.rect, b.rect, (time - a.time) / (b.time - a.time))
    }
    return last.rect
}

// Video keyframes use top-left normalized coordinates. CALayer uses bottom-left points.
func handoffRect(frames: [ScreenFrame], time: Double, videoRect: CGRect,
                 bounds: CGRect, progress: Double) -> CGRect {
    let normalized = screenRect(frames: frames, time: time)
    let inVideo = CGRect(x: videoRect.minX + normalized.minX * videoRect.width,
                         y: videoRect.minY + (1 - normalized.maxY) * videoRect.height,
                         width: normalized.width * videoRect.width,
                         height: normalized.height * videoRect.height)
    return mixRect(inVideo, bounds, smoothProgress(progress))
}

func appKitRect(fromScreenRect rect: CGRect, primaryScreenTop: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryScreenTop - rect.maxY, width: rect.width, height: rect.height)
}

func decodeCaptureRect(_ value: Any?) -> CGRect? {
    if let rect = value as? CGRect { return rect }
    if let dictionary = value as? NSDictionary { return CGRect(dictionaryRepresentation: dictionary as CFDictionary) }
    return nil
}

func captureContentsRect(contentRect: CGRect, scaleFactor: CGFloat,
                         bufferSize: CGSize) -> CGRect {
    guard bufferSize.width > 0, bufferSize.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
    // contentRect already reflects source-to-surface scaling; only convert surface points to pixels.
    let scale = scaleFactor
    let pixels = CGRect(x: contentRect.minX * scale, y: contentRect.minY * scale,
                        width: contentRect.width * scale, height: contentRect.height * scale)
    let clipped = pixels.intersection(CGRect(origin: .zero, size: bufferSize))
    guard !clipped.isEmpty else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
    return CGRect(x: clipped.minX / bufferSize.width, y: clipped.minY / bufferSize.height,
                  width: clipped.width / bufferSize.width, height: clipped.height / bufferSize.height)
}

struct WindowCandidate {
    var id: UInt32
    var processID: Int32
    var bundleIdentifier: String
    var layer: Int
    var onScreen: Bool
    var frame: CGRect
}

func selectClientWindow(_ windows: [WindowCandidate], processID: Int32,
                        bundleIdentifier: String, frontToBack: [UInt32]) -> WindowCandidate? {
    let matches = windows.filter {
        $0.processID == processID && $0.bundleIdentifier == bundleIdentifier &&
        $0.layer == 0 && $0.onScreen && $0.frame.width >= 320 && $0.frame.height >= 180
    }
    for id in frontToBack {
        if let match = matches.first(where: { $0.id == id }) { return match }
    }
    return matches.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
}
