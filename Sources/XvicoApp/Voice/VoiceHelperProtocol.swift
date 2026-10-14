// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Xvico project rights holders.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

/// The privileged endpoint accepts no commands, paths, PIDs or user IDs from
/// callers. Identity comes from the authenticated XPC connection instead.
@objc(XvicoVoiceHelperProtocol)
protocol VoiceHelperProtocol {
    func startSession(_ sessionID: String, withReply reply: @escaping (String?) -> Void)
    func stopSession(withReply reply: @escaping () -> Void)
}

enum VoiceHelperContract {
    static let label = "work.xvico.voice-service"
    static let root = "/Library/Application Support/Xvibe/VoiceService"
    static let executable = "XvicoVoiceDaemon"
    static let consentKey = "xvico.voice.serviceConsent.v1"

    static func validSessionID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString == value
    }
    static func requirement(identifier: String, fingerprint: String) -> String? {
        guard fingerprint.count == 40,
              fingerprint.allSatisfy({ "0123456789ABCDEF".contains($0) }),
              ["work.xvibe.remote", label].contains(identifier) else { return nil }
        return "identifier \"\(identifier)\" and certificate leaf = H\"\(fingerprint)\""
    }
}

enum VoiceRuntimeLocation {
    static let components = [("Resources/packetlogger", "com.apple.packetlogger"),
                             ("Frameworks/PacketDecoder.framework", "com.apple.PacketDecoder")]

    static func imported(in home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Xvico/PacketLoggerRuntime")
    }
    static func hasLayout(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.appendingPathComponent(components[0].0).path)
            && FileManager.default.fileExists(atPath: url.appendingPathComponent(components[1].0).path)
    }
    static func resolve(app: URL, home: URL) -> URL? {
        [app.appendingPathComponent("Contents/Resources/PacketLoggerRuntime"), imported(in: home)]
            .first(where: hasLayout)
    }
}
