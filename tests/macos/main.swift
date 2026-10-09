import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func rejects(_ config: LauncherConfig, _ message: String) {
    do { try config.validate(); fatalError(message) } catch { }
}

let config = try LauncherConfig.load(from: URL(fileURLWithPath: CommandLine.arguments[1]))
check(playbackAction(time: 5, elapsed: 5, appReady: false, ended: false, config: config) == .play, "Start playback while launching")
check(playbackAction(time: 11.4, elapsed: 15, appReady: false, ended: false, config: config) == .hold, "Hold when app is delayed")
check(playbackAction(time: 11.4, elapsed: 20, appReady: true, ended: false, config: config) == .play, "Resume after launch")
check(playbackAction(time: 12.8, elapsed: 21, appReady: true, ended: false, config: config) == .handoff, "Timed handoff")
check(playbackAction(time: 2, elapsed: 4, appReady: true, ended: true, config: config) == .handoff, "Short video must hand off")
check(playbackAction(time: 2, elapsed: 4, appReady: false, ended: true, config: config) == .hold, "Short video waits for client")
check(playbackAction(time: 11.4, elapsed: 61, appReady: false, ended: false, config: config) == .timeout, "Bound the wait")
check(playbackAction(time: 0, elapsed: 61, appReady: true, ended: false, config: config) == .timeout, "Broken media cannot block forever")
var bad = config
bad.volume = 2
rejects(bad, "Reject invalid volume")
bad = config
bad.transitionStart = 1
rejects(bad, "Reject transition before hold")
bad = config
bad.maxWaitSeconds = .infinity
rejects(bad, "Reject nonfinite timeout")
bad = config
bad.video = " "
rejects(bad, "Reject empty video")
let root = URL(fileURLWithPath: "/tmp/app resources")
check(config.videoURL(relativeTo: root).path == "/tmp/app resources/media/startup.mp4", "Paths with spaces")
bad.video = "/tmp/personal video.mp4"
check(bad.videoURL(relativeTo: root).path == bad.video, "Absolute custom video")
print("Passed 14 configuration, playback and path checks.")
