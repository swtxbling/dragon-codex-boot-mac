import Foundation

// Callers pass fixed event names and Boolean results, never titles, pixels or client content.
func reportEvent(_ event: String) {
    print(event)
    guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
    let folder = support.appendingPathComponent("dragon-codex-boot", isDirectory: true)
    let url = folder.appendingPathComponent("launcher.log")
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size < 1_000_000 else { return }
        let line = ISO8601DateFormatter().string(from: Date()) + " " + event + "\n"
        if let data = line.data(using: .utf8) { try handle.write(contentsOf: data) }
    } catch { /* Diagnostics must never block launch or handoff. */ }
}
