import AppKit
import CoreMedia
import CoreVideo
import IOSurface
import ScreenCaptureKit

final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((IOSurfaceRef, CGRect) -> Void)?
    var onError: ((Error) -> Void)?
    private var stream: SCStream?
    private var currentSample: CMSampleBuffer?
    private let queue = DispatchQueue(label: "dragon-codex-boot.window-capture")
    private let pendingLock = NSLock()
    private var pending = false
    private var stopped = false

    func start(window: SCWindow, scale: CGFloat) {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // Fixed capture size; only the CALayer frame changes during the animation.
        let cappedScale = min(scale, 2560 / max(window.frame.width, window.frame.height))
        config.width = max(2, Int(window.frame.width * cappedScale))
        config.height = max(2, Int(window.frame.height * cappedScale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false
        if #available(macOS 14.0, *) { config.ignoreShadowsSingleWindow = true }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            stream.startCapture { [weak self] error in
                if let error {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.stopped else { return }
                        self.onError?(error)
                    }
                }
            }
        } catch { onError?(error) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let buffer = sampleBuffer.imageBuffer,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let status = info[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return }
        let width = CGFloat(CVPixelBufferGetWidth(buffer)), height = CGFloat(CVPixelBufferGetHeight(buffer))
        var normalized = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let rect = decodeCaptureRect(info[.contentRect]),
           let scale = info[.scaleFactor] as? CGFloat {
            normalized = captureContentsRect(contentRect: rect, scaleFactor: scale,
                                             bufferSize: CGSize(width: width, height: height))
        }
        pendingLock.lock()
        if pending { pendingLock.unlock(); return }
        pending = true
        pendingLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.pendingLock.lock(); self.pending = false; self.pendingLock.unlock() }
            guard !self.stopped else { return }
            // Retain exactly the displayed frame until the next surface replaces it.
            self.currentSample = sampleBuffer
            self.onFrame?(surface, normalized)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.onError?(error)
        }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        onFrame = nil
        onError = nil
        let closingStream = stream
        closingStream?.stopCapture { [weak self] _ in
            if let self { try? closingStream?.removeStreamOutput(self, type: .screen) }
        }
        stream = nil
        currentSample = nil
        reportEvent("Live-window capture stop requested.")
    }
}
