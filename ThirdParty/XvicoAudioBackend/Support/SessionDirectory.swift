import Foundation
import Darwin

// Privileged services must never write through a pathname in a user-writable
// directory. Pin the directory inode and use no-follow, exclusive openat calls.
final class SessionDirectory {
    enum Failure: Error { case invalidDirectory, invalidName, invalidFile, io(Int32) }
    private let descriptor: Int32
    private let ownerUID: uid_t
    init(_ url: URL, ownerUID: uid_t) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.io(errno) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == ownerUID else {
            close(fd); throw Failure.invalidDirectory
        }
        descriptor = fd; self.ownerUID = ownerUID
    }
    deinit { close(descriptor) }
    private func validate(_ name: String) throws {
        guard ["stop", "backend-ended", "ready.json"].contains(name) else { throw Failure.invalidName }
    }
    func exists(_ name: String) -> Bool {
        guard (try? validate(name)) != nil else { return false }
        var info = stat()
        return fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0
            && info.st_mode & S_IFMT == S_IFREG && info.st_uid == ownerUID
            && info.st_nlink == 1
    }
    func create(_ name: String, data: Data = Data()) throws {
        try validate(name)
        let fd = openat(descriptor, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            // Repeated stop signals are harmless. Never open/truncate an existing file.
            if errno == EEXIST && name != "ready.json" && exists(name) { return }
            throw Failure.io(errno)
        }
        defer { close(fd) }
        guard fchown(fd, ownerUID, gid_t.max) == 0 else { throw Failure.io(errno) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.io(errno) }
                offset += count
            }
        }
    }
    func read(_ name: String, maximumBytes: Int = 4096) throws -> Data {
        try validate(name)
        let fd = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.io(errno) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == ownerUID, info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= maximumBytes else { throw Failure.invalidFile }
        var bytes = [UInt8](repeating: 0, count: maximumBytes + 1)
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        guard count >= 0, count <= maximumBytes else { throw Failure.invalidFile }
        return Data(bytes.prefix(count))
    }
}
