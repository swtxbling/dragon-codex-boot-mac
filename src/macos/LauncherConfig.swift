import Foundation

struct LauncherConfig: Codable {
    var video: String = "media/startup.mp4"
    var appBundleIdentifier: String = "com.openai.codex"
    var appPath: String? = nil
    var holdAt: Double = 11.3
    var transitionStart: Double = 12.7
    var fadeDuration: Double = 0.8
    var maxWaitSeconds: Double = 60
    var volume: Double = 1
    var playerWidth: Double = 1280
    var playerHeight: Double = 720
    var transitionEnd: Double? = nil
    var screenFrames: [ScreenFrame]? = nil

    var handoffEnd: Double { transitionEnd ?? (transitionStart + fadeDuration) }
    var handoffFrames: [ScreenFrame] {
        screenFrames ?? [
            ScreenFrame(time: transitionStart, x: 0.123, y: 0.094, width: 0.736, height: 0.725),
            ScreenFrame(time: handoffEnd, x: 0, y: 0, width: 1, height: 1)
        ]
    }

    static func load(from url: URL) throws -> LauncherConfig {
        let config = try JSONDecoder().decode(LauncherConfig.self, from: Data(contentsOf: url))
        try config.validate()
        return config
    }

    func validate() throws {
        guard !video.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !appBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              holdAt.isFinite, transitionStart.isFinite, fadeDuration.isFinite,
              maxWaitSeconds.isFinite, volume.isFinite,
              playerWidth.isFinite, playerHeight.isFinite,
              holdAt >= 0, transitionStart >= holdAt,
              fadeDuration > 0, fadeDuration <= 10,
              maxWaitSeconds >= 1, maxWaitSeconds <= 300,
              (0...1).contains(volume), playerWidth >= 320, playerHeight >= 180 else {
            throw LauncherError.invalidConfiguration
        }
        guard handoffEnd.isFinite, handoffEnd > transitionStart, handoffEnd - transitionStart <= 10,
              handoffFrames.count >= 2 else { throw LauncherError.invalidConfiguration }
        for (index, frame) in handoffFrames.enumerated() {
            guard frame.time.isFinite, frame.x.isFinite, frame.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite,
                  frame.x >= 0, frame.y >= 0, frame.width > 0, frame.height > 0,
                  frame.x + frame.width <= 1, frame.y + frame.height <= 1,
                  index == 0 || frame.time > handoffFrames[index - 1].time else {
                throw LauncherError.invalidConfiguration
            }
        }
    }

    func videoURL(relativeTo resources: URL) -> URL {
        let path = NSString(string: video).expandingTildeInPath
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return resources.appendingPathComponent(path)
    }
}

enum LauncherError: LocalizedError {
    case invalidConfiguration
    case appNotFound
    case unreadableVideo
    case launchTimeout

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Invalid launcher.json. Check timing, volume and window dimensions."
        case .appNotFound: return "Codex was not found. Install Codex or set appPath in launcher.json to its .app path."
        case .unreadableVideo: return "The startup video is missing or unreadable. Check video in launcher.json."
        case .launchTimeout: return "Codex did not finish launching within the configured timeout. Try opening it directly."
        }
    }
}

enum PlaybackAction: Equatable {
    case play, hold, handoff, timeout
}

// Launch completion is an OS signal, not a guarantee that every client view has loaded.
func playbackAction(time: Double, elapsed: Double, appReady: Bool, ended: Bool,
                    config: LauncherConfig) -> PlaybackAction {
    if appReady && (ended || time >= config.transitionStart) { return .handoff }
    if elapsed >= config.maxWaitSeconds { return .timeout }
    if !appReady && (ended || time >= config.holdAt) { return .hold }
    return .play
}
