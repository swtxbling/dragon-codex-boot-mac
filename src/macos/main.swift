import AppKit
import AVFoundation
import QuartzCore
import ScreenCaptureKit

final class AnimationWindow: NSWindow {
    var onSkip: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onSkip?() } else { super.keyDown(with: event) }
    }
}

final class Launcher: NSObject, NSApplicationDelegate {
    private var config = LauncherConfig()
    private var window: AnimationWindow?
    private var videoLayer: AVPlayerLayer?
    private var liveLayer: CALayer?
    private var player: AVPlayer?
    private var capture: WindowCapture?
    private var timer: Timer?
    private var target: NSRunningApplication?
    private var targetBundleID = ""
    private var selectedWindowID: CGWindowID?
    private var started = Date()
    private var lastProbe = Date.distantPast
    private var captureStarted: Date?
    private var captureReady = false
    private var captureFailed = false
    private var probing = false
    private var useLiveCapture = true
    private var awaitingPermission = false
    private var permissionPrompted = false
    private var videoEnded = false
    private var finishing = false
    private var skipRequested = false
    private var launchCompleted = false
    private var videoWarningShown = false
    private var observers: [NSObjectProtocol] = []
    private let preview = CommandLine.arguments.contains("--preview")
    private let smoke = CommandLine.arguments.contains("--smoke-test")
    private var resources: URL {
        Bundle.main.resourceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
    private var ready: Bool {
        preview || smoke || (launchCompleted && target?.isFinishedLaunching == true &&
                             target?.isTerminated == false && (captureReady || captureFailed || !useLiveCapture))
    }
    private var primaryScreenTop: CGFloat {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }
        return screen?.frame.maxY ?? NSScreen.screens.first?.frame.maxY ?? 0
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            config = try LauncherConfig.load(from: resources.appendingPathComponent("launcher.json"))
            let appURL = try resolveApp()
            targetBundleID = Bundle(url: appURL)?.bundleIdentifier ?? config.appBundleIdentifier
            if CommandLine.arguments.contains("--check") {
                guard FileManager.default.isReadableFile(atPath: config.videoURL(relativeTo: resources).path) else {
                    throw LauncherError.unreadableVideo
                }
                print("Configuration OK; video readable; target: \(appURL.path)")
                print("Legacy capture preflight: \(CGPreflightScreenCaptureAccess()); actual capture is checked on launch.")
                NSApp.terminate(nil)
                return
            }
            if !preview && !smoke {
                reportEvent("Legacy capture preflight: \(CGPreflightScreenCaptureAccess()).")
            }
            target = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first
            showPlayer()
            started = Date()
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            if smoke {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.finish(immediate: true) }
            } else if !preview { launch(appURL) }
        } catch { fail(error) }
    }

    private func showPermissionPrompt() {
        guard !permissionPrompted, !finishing else { return }
        permissionPrompted = true
        awaitingPermission = true
        player?.pause()
        window?.orderOut(nil)
        reportEvent("ScreenCaptureKit explicitly denied capture permission.")
        let alert = NSAlert()
        alert.messageText = "实时渐进交接需要屏幕录制权限"
        alert.informativeText = "macOS 的实际捕获接口拒绝了当前版本的访问。请在「屏幕与系统音频录制」中允许 Dragon Codex Boot，再重新打开。若开关已经开启，更新后的签名可能与旧授权不匹配。画面仅用于本机内存中的渐进交接。"
        alert.addButton(withTitle: "前往授权")
        alert.addButton(withTitle: "本次只播放动画")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            NSApp.terminate(nil)
        case .alertSecondButtonReturn:
            useLiveCapture = false
            awaitingPermission = false
            // Time spent deciding permission must not consume the playback timeout.
            started = Date()
            window?.makeKeyAndOrderFront(nil)
            player?.play()
        default:
            NSApp.terminate(nil)
        }
    }

    private func resolveApp() throws -> URL {
        if preview || smoke { return Bundle.main.bundleURL }
        if let path = config.appPath, !path.isEmpty {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            guard url.pathExtension == "app", Bundle(url: url)?.bundleIdentifier != nil,
                  Bundle(url: url)?.bundleIdentifier != Bundle.main.bundleIdentifier,
                  url.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else { throw LauncherError.appNotFound }
            return url
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.appBundleIdentifier),
              Bundle(url: url)?.bundleIdentifier != Bundle.main.bundleIdentifier,
              url.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else { throw LauncherError.appNotFound }
        return url
    }

    private func windowInfo() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private func bounds(of id: CGWindowID, in info: [[String: Any]]) -> CGRect? {
        guard let item = info.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }),
              let dictionary = item[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
              rect.width >= 320, rect.height >= 180 else { return nil }
        return appKitRect(fromScreenRect: rect, primaryScreenTop: primaryScreenTop)
    }

    private func existingClientFrame() -> CGRect? {
        guard let target else { return nil }
        let info = windowInfo()
        for item in info where (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == target.processIdentifier &&
            (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 {
            if let id = (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
               let rect = bounds(of: id, in: info) { return rect }
        }
        return nil
    }

    private func showPlayer() {
        // Cover the client's entire window, including any video letterboxing.
        let available = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let rect = existingClientFrame() ?? available
        let window = AnimationWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = preview ? "Dragon Codex Boot · 效果预览" : "Dragon Codex Boot"
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.onSkip = { [weak self] in self?.skip() }
        let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        let root = CALayer()
        root.frame = view.bounds
        root.backgroundColor = NSColor.black.cgColor
        root.cornerRadius = 12
        root.masksToBounds = true
        view.layer = root
        let item = AVPlayerItem(url: config.videoURL(relativeTo: resources))
        let player = AVPlayer(playerItem: item)
        player.volume = Float(config.volume)
        let videoLayer = AVPlayerLayer(player: player)
        videoLayer.frame = root.bounds
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        videoLayer.videoGravity = .resizeAspect
        root.addSublayer(videoLayer)
        let liveLayer = CALayer()
        liveLayer.frame = root.bounds
        liveLayer.contentsGravity = .resize
        liveLayer.opacity = 0
        liveLayer.backgroundColor = NSColor.white.cgColor
        liveLayer.masksToBounds = true
        root.addSublayer(liveLayer)
        if preview || smoke { liveLayer.contents = previewImage() }
        window.contentView = view
        self.window = window
        self.player = player
        self.videoLayer = videoLayer
        self.liveLayer = liveLayer
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                               object: item, queue: .main) { [weak self] _ in self?.videoEnded = true })
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        player.play()
    }

    private func previewImage() -> CGImage? {
        // Synthetic UI for permission-free visual checks; never presents it as a real client.
        let image = NSImage(size: NSSize(width: 1280, height: 800), flipped: false) { _ in
            NSColor(calibratedRed: 0.98, green: 0.98, blue: 1, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 1280, height: 800).fill()
            NSColor(calibratedRed: 0.91, green: 0.9, blue: 0.97, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 280, height: 800).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 25, weight: .medium), .foregroundColor: NSColor.darkGray]
            ("交接效果预览 · 示例界面" as NSString).draw(at: NSPoint(x: 340, y: 700), withAttributes: attributes)
            for index in 0..<4 {
                NSColor(calibratedRed: 0.8 + Double(index) * 0.03, green: 0.79, blue: 0.92, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 340, y: 540 - index * 110, width: 840 - index * 80, height: 60), xRadius: 15, yRadius: 15).fill()
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func launch(_ url: URL) {
        let options = NSWorkspace.OpenConfiguration()
        options.activates = false
        options.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: options) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self, !self.finishing else { return }
                if let error { self.fail(error); return }
                guard let app else { self.fail(LauncherError.appNotFound); return }
                self.target = app
                self.launchCompleted = true
                reportEvent("Client launch completed.")
                if self.skipRequested { self.finish(immediate: true); return }
                // Restore/show the client's own window behind the opaque animation overlay.
                app.activate(options: [.activateAllWindows])
                self.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func probeClient() {
        guard let target, launchCompleted, !preview, !smoke, !finishing,
              Date().timeIntervalSince(lastProbe) >= 0.5 else { return }
        lastProbe = Date()
        if let id = selectedWindowID {
            if let rect = bounds(of: id, in: windowInfo()) { alignOverlay(rect) }
            return
        }
        if !useLiveCapture || captureFailed {
            if let rect = existingClientFrame() { alignOverlay(rect) }
            return
        }
        guard !probing else { return }
        probing = true
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self, !self.finishing else { return }
                self.probing = false
                if let error { self.captureUnavailable(error); return }
                guard let content else { return }
                let info = self.windowInfo()
                let order = info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
                let candidates = content.windows.compactMap { window -> WindowCandidate? in
                    guard let app = window.owningApplication else { return nil }
                    return WindowCandidate(id: window.windowID, processID: app.processID, bundleIdentifier: app.bundleIdentifier,
                                           layer: window.windowLayer, onScreen: window.isOnScreen, frame: window.frame)
                }
                guard let selected = selectClientWindow(candidates, processID: target.processIdentifier,
                                                        bundleIdentifier: self.targetBundleID, frontToBack: order),
                      let selectedWindow = content.windows.first(where: { $0.windowID == selected.id }),
                      let rect = self.bounds(of: selected.id, in: info) else { return }
                self.selectedWindowID = selected.id
                self.alignOverlay(rect)
                let screen = NSScreen.screens.max { $0.frame.intersection(rect).width * $0.frame.intersection(rect).height < $1.frame.intersection(rect).width * $1.frame.intersection(rect).height }
                let capture = WindowCapture()
                capture.onFrame = { [weak self] surface, contentsRect in
                    guard let self, !self.finishing else { return }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.liveLayer?.contents = surface
                    self.liveLayer?.contentsRect = contentsRect
                    CATransaction.commit()
                    if !self.captureReady { reportEvent("Live client window ready.") }
                    self.captureReady = true
                }
                capture.onError = { [weak self] error in self?.captureUnavailable(error) }
                self.capture = capture
                self.captureStarted = Date()
                capture.start(window: selectedWindow, scale: screen?.backingScaleFactor ?? 2)
            }
        }
    }

    private func alignOverlay(_ rect: CGRect) {
        guard !finishing, let window, window.frame != rect else { return }
        window.setFrame(rect, display: true)
    }

    private func captureUnavailable(_ error: Error?) {
        guard !captureFailed, !finishing else { return }
        captureFailed = true
        captureReady = false
        liveLayer?.opacity = 0
        liveLayer?.contents = nil
        capture?.stop()
        capture = nil
        if requiresScreenCapturePermission(error) {
            showPermissionPrompt()
            return
        }
        reportEvent("Live-window capture unavailable; using aligned fade handoff.")
    }

    private func tick() {
        guard !finishing, !awaitingPermission else { return }
        if skipRequested && launchCompleted { finish(immediate: true); return }
        if target?.isTerminated == true && launchCompleted { fail(LauncherError.appNotFound); return }
        probeClient()
        if let captureStarted, !captureReady, !captureFailed, Date().timeIntervalSince(captureStarted) > 3 {
            captureUnavailable(nil)
        }
        let elapsed = Date().timeIntervalSince(started)
        if player?.currentItem?.status == .failed && !videoWarningShown {
            videoWarningShown = true
            videoEnded = true
            fputs("Video playback failed; handing off when the client is ready.\n", stderr)
        }
        let seconds = player?.currentTime().seconds ?? 0
        let time = seconds.isFinite ? seconds : 0
        switch playbackAction(time: time, elapsed: elapsed, appReady: ready, ended: videoEnded, config: config) {
        case .handoff:
            if videoEnded && time < config.transitionStart { finish(immediate: false); return }
            let progress = min(1, max(0, (time - config.transitionStart) / (config.handoffEnd - config.transitionStart)))
            renderHandoff(time: time, progress: progress)
            if progress >= 1 || videoEnded { finish(immediate: false) }
        case .timeout: fail(LauncherError.launchTimeout)
        case .hold: player?.pause()
        case .play: if !skipRequested && !videoEnded { player?.play() }
        }
    }

    private func renderHandoff(time: Double, progress: Double) {
        guard let bounds = window?.contentView?.bounds else { return }
        let videoRect = videoLayer?.videoRect ?? aspectFitRect(content: CGSize(width: config.playerWidth, height: config.playerHeight), in: bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if captureReady || preview || smoke {
            liveLayer?.frame = handoffRect(frames: config.handoffFrames, time: time, videoRect: videoRect, bounds: bounds, progress: progress)
            liveLayer?.opacity = Float(smoothProgress(progress))
            liveLayer?.cornerRadius = 10 * (1 - smoothProgress(progress))
        } else {
            window?.alphaValue = 1 - smoothProgress(progress)
        }
        CATransaction.commit()
    }

    private func skip() {
        skipRequested = true
        reportEvent("Animation skipped.")
        player?.pause()
        window?.orderOut(nil)
        capture?.stop()
        liveLayer?.contents = nil
        if preview || smoke || launchCompleted { finish(immediate: true) }
    }

    private func finish(immediate: Bool) {
        guard !finishing else { return }
        finishing = true
        timer?.invalidate()
        // Keep the final live frame during the short handoff; release capture on termination.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = immediate ? 0 : min(config.fadeDuration, 0.35)
            window?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.activateClientAndExit()
        }
    }

    private func activateClientAndExit() {
        player?.pause()
        liveLayer?.contents = nil
        capture?.stop()
        capture = nil
        if preview || smoke { reportEvent("Preview completed."); NSApp.terminate(nil); return }
        guard let target, !target.isTerminated else { NSApp.terminate(nil); return }
        let activated: Bool
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: target)
            activated = target.activate(from: NSRunningApplication.current, options: [.activateAllWindows])
        } else {
            activated = target.activate(options: [.activateAllWindows])
        }
        reportEvent("Client handoff: activation requested, accepted=\(activated).")
        if activated { NSApp.terminate(nil); return }
        guard let url = target.bundleURL else { NSApp.terminate(nil); return }
        let options = NSWorkspace.OpenConfiguration()
        options.activates = true
        options.addsToRecentItems = false
        // One bounded Launch Services retry if cooperative activation was declined.
        NSWorkspace.shared.openApplication(at: url, configuration: options) { _, error in
            DispatchQueue.main.async {
                reportEvent("Client activation retry completed, accepted=\(error == nil).")
                NSApp.terminate(nil)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
    }

    private func fail(_ error: Error) {
        finishing = true
        timer?.invalidate()
        player?.pause()
        capture?.stop()
        liveLayer?.contents = nil
        window?.orderOut(nil)
        fputs("\(error.localizedDescription)\n", stderr)
        if CommandLine.arguments.contains("--check") || smoke { exit(1) }
        let alert = NSAlert()
        alert.messageText = "Dragon Codex Boot"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        player?.pause()
        liveLayer?.contents = nil
        capture?.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let launcher = Launcher()
app.delegate = launcher
app.run()
