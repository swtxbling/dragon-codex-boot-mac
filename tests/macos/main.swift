import Foundation
import ScreenCaptureKit

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

func rejects(_ config: LauncherConfig, _ message: String) {
    do { try config.validate(); fatalError(message) } catch { }
}

check(!requiresScreenCapturePermission(nil), "A successful capture must not ask for permission")
check(requiresScreenCapturePermission(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)),
      "An explicit ScreenCaptureKit denial must offer authorization")
check(!requiresScreenCapturePermission(NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.internalError.rawValue)),
      "A capture service failure must not be misreported as denied permission")
check(!requiresScreenCapturePermission(NSError(domain: NSCocoaErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)),
      "An unrelated error with the same number must not ask for screen authorization")
print("Passed capture permission denial classification checks.")

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

func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
let bounds = CGRect(x: 0, y: 0, width: 1200, height: 900)
let fitted = aspectFitRect(content: CGSize(width: 1920, height: 1080), in: bounds)
check(near(fitted.minY, 112.5) && near(fitted.height, 675), "Letterbox must map into actual video bounds")
let initial = handoffRect(frames: config.handoffFrames, time: config.transitionStart,
                          videoRect: fitted, bounds: bounds, progress: 0)
check(near(initial.width, 883.2) && near(initial.minX, 147.6), "Map screen frame to correct video position")
let end = handoffRect(frames: config.handoffFrames, time: config.handoffEnd,
                      videoRect: fitted, bounds: bounds, progress: 1)
check(end == bounds, "Final live image must exactly match underlying client window")
var previous = initial
for index in 1...120 {
    let progress = Double(index) / 120
    let time = config.transitionStart + (config.handoffEnd - config.transitionStart) * progress
    let rect = handoffRect(frames: config.handoffFrames, time: time, videoRect: fitted, bounds: bounds, progress: progress)
    check(rect.width >= previous.width - 0.001 && rect.height >= previous.height - 0.001, "Reveal must grow continuously")
    check(bounds.contains(rect), "Reveal cannot overflow the client window")
    previous = rect
}
check(smoothProgress(-1) == 0 && smoothProgress(2) == 1 && smoothProgress(0.5) == 0.5, "Clamp easing")
let converted = appKitRect(fromScreenRect: CGRect(x: -1200, y: -900, width: 1000, height: 700), primaryScreenTop: 1000)
check(converted == CGRect(x: -1200, y: 1200, width: 1000, height: 700), "Displays above/left of the primary screen")
let surfaceContent = CGRect(x: 0, y: 0, width: 640, height: 400)
let decoded = decodeCaptureRect(surfaceContent.dictionaryRepresentation as Any)
check(decoded == surfaceContent, "Decode actual ScreenCaptureKit dictionary metadata")
check(decodeCaptureRect(surfaceContent) == surfaceContent && decodeCaptureRect("invalid") == nil, "Handle direct CGRect and invalid metadata")
let fullCrop = captureContentsRect(contentRect: decoded!, scaleFactor: 2,
                                  bufferSize: CGSize(width: 1280, height: 800))
check(fullCrop == CGRect(x: 0, y: 0, width: 1, height: 1), "Retina capture must not double point coordinates")
let paddedCrop = captureContentsRect(contentRect: CGRect(x: 10, y: 20, width: 800, height: 500), scaleFactor: 2,
                                    bufferSize: CGSize(width: 1640, height: 1080))
check(near(paddedCrop.minX, 20.0 / 1640) && near(paddedCrop.height, 1000.0 / 1080), "Crop padded capture surface")
let candidates = [
    WindowCandidate(id: 1, processID: 77, bundleIdentifier: "test.client", layer: 0, onScreen: true, frame: bounds),
    WindowCandidate(id: 2, processID: 77, bundleIdentifier: "test.client", layer: 0, onScreen: true, frame: bounds),
    WindowCandidate(id: 3, processID: 99, bundleIdentifier: "test.client", layer: 0, onScreen: true, frame: bounds),
    WindowCandidate(id: 4, processID: 77, bundleIdentifier: "other.app", layer: 0, onScreen: true, frame: bounds),
    WindowCandidate(id: 5, processID: 77, bundleIdentifier: "test.client", layer: 2, onScreen: true, frame: bounds),
    WindowCandidate(id: 6, processID: 77, bundleIdentifier: "test.client", layer: 0, onScreen: false, frame: bounds)
]
check(selectClientWindow(candidates, processID: 77, bundleIdentifier: "test.client", frontToBack: [3,4,5,6,2,1])?.id == 2,
      "Capture only the foremost normal window belonging to the exact launched process and bundle")
check(selectClientWindow(candidates, processID: 0, bundleIdentifier: "test.client", frontToBack: []) == nil,
      "Never capture a different process as fallback")
bad = config
bad.screenFrames = []
rejects(bad, "Reject absent keyframes")
bad = config
bad.screenFrames = [ScreenFrame(time: 1, x: 0, y: 0, width: 1, height: 1), ScreenFrame(time: 1, x: 0, y: 0, width: 1, height: 1)]
rejects(bad, "Reject duplicate keyframe times")
bad = config
bad.transitionEnd = config.transitionStart
rejects(bad, "Reject zero duration handoff")
print("Passed handoff geometry, 120-step continuity, multi-display coordinates, Retina crop and exact-window selection checks.")
