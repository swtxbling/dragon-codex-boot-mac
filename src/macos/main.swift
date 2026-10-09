import AppKit
import AVFoundation
import AVKit

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
    private var player: AVPlayer?
    private var timer: Timer?
    private var target: NSRunningApplication?
    private var started = Date()
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
        preview || smoke || (launchCompleted && target?.isFinishedLaunching == true && target?.isTerminated == false)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            config = try LauncherConfig.load(from: resources.appendingPathComponent("launcher.json"))
            let appURL = try resolveApp()
            if CommandLine.arguments.contains("--check") {
                guard FileManager.default.isReadableFile(atPath: config.videoURL(relativeTo: resources).path) else {
                    throw LauncherError.unreadableVideo
                }
                print("Configuration OK; video readable; target: \(appURL.path)")
                NSApp.terminate(nil)
                return
            }
            showPlayer()
            started = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
            if smoke {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.handoff() }
            } else if !preview {
                launch(appURL)
            }
        } catch { fail(error) }
    }

    private func resolveApp() throws -> URL {
        if preview || smoke { return Bundle.main.bundleURL }
        if let path = config.appPath, !path.isEmpty {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            guard url.pathExtension == "app", Bundle(url: url)?.bundleIdentifier != nil,
                  url.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else {
                throw LauncherError.appNotFound
            }
            return url
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.appBundleIdentifier),
              url.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL else {
            throw LauncherError.appNotFound
        }
        return url
    }

    private func showPlayer() {
        let available = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let scale = min(1, min(available.width / config.playerWidth, available.height / config.playerHeight))
        let size = NSSize(width: config.playerWidth * scale, height: config.playerHeight * scale)
        let rect = NSRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                          width: size.width, height: size.height)
        let window = AnimationWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Dragon Codex Boot"
        window.backgroundColor = .black
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.onSkip = { [weak self] in self?.skip() }
        let item = AVPlayerItem(url: config.videoURL(relativeTo: resources))
        let player = AVPlayer(playerItem: item)
        player.volume = Float(config.volume)
        let view = AVPlayerView(frame: NSRect(origin: .zero, size: size))
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        window.contentView = view
        self.window = window
        self.player = player
        observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                               object: item, queue: .main) { [weak self] _ in
            self?.videoEnded = true
        })
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        player.play()
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
                print("Client launch completed.")
                if self.skipRequested && self.ready { self.handoff() }
            }
        }
    }

    private func tick() {
        guard !finishing else { return }
        if skipRequested && ready { handoff(); return }
        let elapsed = Date().timeIntervalSince(started)
        if player?.currentItem?.status == .failed && !videoWarningShown {
            videoWarningShown = true
            videoEnded = true
            // A media failure must not strand the client behind an overlay.
            fputs("Video playback failed; handing off to Codex when launch completes.\n", stderr)
        }
        let seconds = player?.currentTime().seconds ?? 0
        switch playbackAction(time: seconds.isFinite ? seconds : 0, elapsed: elapsed,
                              appReady: ready, ended: videoEnded, config: config) {
        case .handoff: handoff()
        case .timeout: fail(LauncherError.launchTimeout)
        case .hold: player?.pause()
        case .play: if !skipRequested && !videoEnded { player?.play() }
        }
    }

    private func skip() {
        skipRequested = true
        print("Animation skipped.")
        player?.pause()
        window?.orderOut(nil)
        if ready { handoff() }
    }

    private func handoff() {
        guard !finishing else { return }
        finishing = true
        timer?.invalidate()
        if !preview && !smoke {
            let activated = target?.activate(options: [.activateAllWindows]) ?? false
            print("Client handoff: activation requested, accepted=\(activated).")
        } else {
            print("Preview completed.")
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = skipRequested ? 0 : config.fadeDuration
            window?.animator().alphaValue = 0
        } completionHandler: {
            NSApp.terminate(nil)
        }
    }

    private func fail(_ error: Error) {
        finishing = true
        timer?.invalidate()
        player?.pause()
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
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let launcher = Launcher()
app.delegate = launcher
app.run()
