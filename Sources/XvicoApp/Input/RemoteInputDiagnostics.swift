import Combine
import Foundation

struct RemoteOutputDiagnostic: Equatable {
    var kind: String
    var value: String
    var targetBundleID: String
    var sceneName: String?
    var sent: Bool
}

// High-rate hardware diagnostics have their own observation scope. Updating
// them must not invalidate the window or restart native scroll rendering.
@MainActor
final class RemoteInputDiagnostics: ObservableObject {
    @Published var touchCount = 0
    @Published var buttonCount = 0
    @Published var lastButton = "尚未收到实体按键输入"
    @Published private(set) var lastAction = "准备就绪"
    @Published private(set) var lastOutput: RemoteOutputDiagnostic?
    private var lastActionUpdate = -Double.infinity
    private var lastOutputUpdate = -Double.infinity

    func recordOutput(_ output: RemoteOutputDiagnostic, throttled: Bool = false,
                      timestamp: Double = ProcessInfo.processInfo.systemUptime) {
        guard !throttled || timestamp - lastOutputUpdate >= 0.25 else { return }
        guard output != lastOutput else { return }
        lastOutputUpdate = timestamp
        lastOutput = output
    }

    func recordAction(_ text: String, throttled: Bool = false,
                      timestamp: Double = ProcessInfo.processInfo.systemUptime) {
        guard !throttled || timestamp - lastActionUpdate >= 0.25 else { return }
        guard text != lastAction else { return }
        lastActionUpdate = timestamp
        lastAction = text
    }
}
