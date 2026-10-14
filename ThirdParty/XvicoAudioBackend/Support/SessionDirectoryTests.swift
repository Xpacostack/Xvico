import Foundation
import Darwin

@main enum SessionDirectoryTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("xvico-session-test-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let session = root.appendingPathComponent("session")
        try fm.createDirectory(at: session, withIntermediateDirectories: true)
        let sentinel = root.appendingPathComponent("sentinel")
        let original = Data("must never be truncated".utf8)
        try original.write(to: sentinel)
        let directory = try SessionDirectory(session, ownerUID: getuid())
        for marker in ["stop", "backend-ended", "ready.json"] {
            let link = session.appendingPathComponent(marker)
            try fm.createSymbolicLink(at: link, withDestinationURL: sentinel)
            do { try directory.create(marker); fatalError("followed symlink: \(marker)") }
            catch { }
            guard try Data(contentsOf: sentinel) == original, !directory.exists(marker) else {
                fatalError("marker modified a symlink target")
            }
            do { _ = try directory.read(marker); fatalError("read symlink") } catch { }
            try fm.removeItem(at: link)
        }
        try directory.create("stop"); try directory.create("stop")
        guard directory.exists("stop") else { fatalError("missing stop marker") }
        try directory.create("ready.json", data: Data("{}".utf8))
        guard try directory.read("ready.json") == Data("{}".utf8) else { fatalError("metadata changed") }
        do { try directory.create("../sentinel"); fatalError("accepted traversal") } catch { }
        let moved = root.appendingPathComponent("moved")
        try fm.moveItem(at: session, to: moved)
        try fm.createSymbolicLink(at: session, withDestinationURL: root)
        try directory.create("backend-ended")
        guard fm.fileExists(atPath: moved.appendingPathComponent("backend-ended").path),
              !fm.fileExists(atPath: root.appendingPathComponent("backend-ended").path) else {
            fatalError("directory pathname swap redirected a privileged write")
        }
        print("PASS: three marker symlinks, metadata reads, traversal, repeated stop and directory replacement are safe")
    }
}
