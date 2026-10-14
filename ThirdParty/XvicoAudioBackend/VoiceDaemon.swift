import Foundation
import Darwin

private struct ActiveSession {
    let owner: UUID
    let process: Process
    let directory: SessionDirectory
}

private final class SessionController {
    private let queue = DispatchQueue(label: "work.xvico.voice-service.sessions")
    private var active: ActiveSession?
    private var shuttingDown = false

    func start(id: String, owner: UUID, uid: uid_t, pid: pid_t, reply: @escaping (String?) -> Void) {
        queue.async { [self] in
            guard !self.shuttingDown, self.active == nil else { reply("语音后台正在使用或停止中，请稍后重试"); return }
            guard VoiceHelperContract.validSessionID(id), uid >= 500, pid > 1,
                  kill(pid, 0) == 0, let user = getpwuid(uid) else { reply("无效语音会话"); return }
            let directory = URL(fileURLWithPath: String(cString: user.pointee.pw_dir))
                .appendingPathComponent("Library/Caches/Xvibe/VoiceSessions/\(id)")
            guard directory.resolvingSymlinksInPath() == directory else { reply("无效会话目录"); return }
            do {
                let session = try SessionDirectory(directory, ownerUID: uid)
                guard !session.exists("stop"), !session.exists("backend-ended"), !session.exists("ready.json") else {
                    reply("语音会话已经结束，请重新启动"); return
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: VoiceHelperContract.root).appendingPathComponent("XvibeBackendRunner")
                process.arguments = [directory.path, String(uid), String(pid), "compat"]
                process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
                process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                process.terminationHandler = { [weak self] _ in
                    guard let self else { return }
                    self.queue.async {
                        guard self.active?.owner == owner else { return }
                        try? session.create("backend-ended")
                        self.active = nil
                        if self.shuttingDown { exit(0) }
                    }
                }
                try process.run()
                self.active = ActiveSession(owner: owner, process: process, directory: session)
                reply(nil)
            } catch { reply("无法启动已授权语音后台：\(error.localizedDescription)") }
        }
    }
    func stop(owner: UUID, reply: @escaping () -> Void = {}) {
        queue.async {
            if let session = self.active, session.owner == owner {
                // Leave the child alive long enough to restore diagnostic
                // preferences and delete its capture file before it exits.
                try? session.directory.create("stop")
            }
            reply()
        }
    }
    func shutdown() {
        queue.async {
            self.shuttingDown = true
            guard let session = self.active else { exit(0) }
            try? session.directory.create("stop")
        }
    }
}

private final class VoiceEndpoint: NSObject, VoiceHelperProtocol {
    let owner = UUID()
    let uid: uid_t
    let pid: pid_t
    let controller: SessionController
    init(connection: NSXPCConnection, controller: SessionController) {
        uid = connection.effectiveUserIdentifier
        pid = connection.processIdentifier
        self.controller = controller
    }
    func startSession(_ sessionID: String, withReply reply: @escaping (String?) -> Void) {
        controller.start(id: sessionID, owner: owner, uid: uid, pid: pid, reply: reply)
    }
    func stopSession(withReply reply: @escaping () -> Void) { controller.stop(owner: owner, reply: reply) }
}

private final class VoiceListener: NSObject, NSXPCListenerDelegate {
    let controller = SessionController()
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier >= 500, connection.processIdentifier > 1 else { return false }
        let endpoint = VoiceEndpoint(connection: connection, controller: controller)
        connection.exportedInterface = NSXPCInterface(with: VoiceHelperProtocol.self)
        connection.exportedObject = endpoint
        connection.invalidationHandler = { [weak controller] in controller?.stop(owner: endpoint.owner) }
        connection.interruptionHandler = { [weak controller] in controller?.stop(owner: endpoint.owner) }
        connection.resume()
        return true
    }
}

@main enum VoiceDaemon {
    static func main() {
        guard getuid() == 0,
              let requirement = VoiceHelperContract.requirement(identifier: "work.xvibe.remote", fingerprint: BackendSigningIdentity.fingerprint) else { exit(1) }
        let delegate = VoiceListener()
        let listener = NSXPCListener(machServiceName: VoiceHelperContract.label)
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.delegate = delegate
        signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        term.setEventHandler { delegate.controller.shutdown() }
        interrupt.setEventHandler { delegate.controller.shutdown() }
        term.resume(); interrupt.resume(); listener.resume()
        withExtendedLifetime((delegate, listener, term, interrupt)) { RunLoop.current.run() }
    }
}
