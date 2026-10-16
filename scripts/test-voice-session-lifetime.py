#!/usr/bin/env python3
"""Exercise the real runner loop with fake processes/time; no audio or privileges.

Only the runner's @main annotation is removed in a temporary compilation unit.
The original loop and cleanup run unchanged against simulated dependencies.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
runner = root / 'ThirdParty/XvicoAudioBackend/BackendRunner.swift'
harness = r'''
import Foundation
import Darwin

enum Probe {
    static var ticks = 0
    static var stopWritten = false
    static var endedWritten = false
    static var captureJoined = false
    static var routerTerminated = false
    static var reason = "stop"
    static var handlers: [Int32: @convention(c) (Int32) -> Void] = [:]
    static let endTick = 64
    static var elapsed: Double { Double(ticks) * 1800 }
}

// If a wall-clock deadline is reintroduced, this clock crosses it immediately.
struct Date: Comparable {
    let value: Double
    init() { value = Probe.elapsed }
    private init(value: Double) { self.value = value }
    func addingTimeInterval(_ seconds: Double) -> Date { Date(value: value + seconds) }
    static func < (lhs: Date, rhs: Date) -> Bool { lhs.value < rhs.value }
}

func getuid() -> uid_t { 0 }
func kill(_ pid: pid_t, _ value: Int32) -> Int32 {
    Probe.reason == "client" && Probe.ticks >= Probe.endTick ? -1 : 0
}
func signal(_ number: Int32, _ handler: @escaping @convention(c) (Int32) -> Void) {
    Probe.handlers[number] = handler
}
@discardableResult func usleep(_ value: useconds_t) -> Int32 {
    Probe.ticks += 1
    precondition(Probe.ticks <= Probe.endTick, "runner failed to stop")
    if Probe.reason == "signal" && Probe.ticks == Probe.endTick {
        Probe.handlers[SIGTERM]?(SIGTERM)
    }
    return 0
}

struct SessionDirectory {
    init(_ url: URL, ownerUID: uid_t) throws { }
    func exists(_ name: String) -> Bool {
        name == "stop" && (Probe.stopWritten || (Probe.reason == "stop" && Probe.ticks >= Probe.endTick))
    }
    func create(_ name: String) throws {
        if name == "stop" { Probe.stopWritten = true }
        if name == "backend-ended" { Probe.endedWritten = true }
    }
    func read(_ name: String) throws -> Data {
        Data(#"{"capture":"/private/var/tmp/xvibe-voice.test/remote.pklg"}"#.utf8)
    }
}

final class Process {
    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardOutput: Any?
    var standardError: Any?
    private var active = false
    private var capture: Bool { executableURL?.lastPathComponent == "XvibeVoiceCapture" }
    var isRunning: Bool {
        active && !(Probe.ticks >= Probe.endTick && Probe.reason == (capture ? "capture" : "router"))
    }
    func run() throws { active = true }
    func terminate() { active = false; if !capture { Probe.routerTerminated = true } }
    func waitUntilExit() {
        if capture {
            precondition(Probe.stopWritten, "capture must receive stop before joining")
            Probe.captureJoined = true
        }
        active = false
    }
}

@main enum LifetimeTests {
    static func main() throws {
        Probe.reason = CommandLine.arguments[4]
        try BackendRunner.main()
        precondition(Probe.elapsed >= 32 * 3600, "session stopped at a fixed deadline")
        precondition(Probe.stopWritten && Probe.endedWritten, "missing cleanup markers")
        if Probe.reason != "capture" { precondition(Probe.captureJoined) }
        if Probe.reason != "router" { precondition(Probe.routerTerminated) }
        print("PASS: 32 simulated hours, \(Probe.reason) teardown")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='xvico-lifetime-') as folder:
    tmp = Path(folder)
    source = runner.read_text()
    assert source.count('@main enum BackendRunner') == 1
    (tmp / 'Runner.swift').write_text(source.replace('@main enum BackendRunner', 'enum BackendRunner'))
    # The command-line contract only accepts standard/compat. Map the selected
    # simulated termination reason through the test environment instead.
    harness = harness.replace('Probe.reason = CommandLine.arguments[4]',
                              'Probe.reason = ProcessInfo.processInfo.environment["XVICO_TEST_END"]!')
    (tmp / 'Harness.swift').write_text(harness)
    binary = tmp / 'lifetime-tests'
    subprocess.run(['swiftc', '-O', '-parse-as-library', tmp / 'Runner.swift',
                    tmp / 'Harness.swift', '-o', binary], check=True)
    import os
    for reason in ['stop', 'client', 'capture', 'router', 'signal']:
        subprocess.run([binary, '/unused/session', '501', '123', 'compat'],
                       env={**os.environ, 'XVICO_TEST_END': reason}, check=True)
