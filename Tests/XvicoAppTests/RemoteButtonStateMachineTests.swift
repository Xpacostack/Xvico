import XCTest
@testable import XvicoApp

final class RemoteButtonStateMachineTests: XCTestCase {
    private typealias Machine = RemoteButtonStateMachine
    private typealias Effect = Machine.Effect
    private let context = Machine.Context(application: "test.editor", scene: nil,
        ringToggleKey: "", volumeMode: .key, volumeScrollStep: 50)
    private let plain = KeyBinding(action: .key, value: "A", modifiers: [.control])
    private var segmented: KeyBinding {
        .init(action: .key, value: "Fn", doubleClickEnabled: true, doubleClickValue: "F6")
    }
    private var long: KeyBinding {
        var binding = KeyBinding(action: .key, value: "A", longPressEnabled: true,
            longPressValue: "F7", longPressModifiers: [.option])
        binding.longPressRightModifiers = [.option]
        return binding
    }
    private func timer(_ effects: [Effect], file: StaticString = #filePath, line: UInt = #line) throws -> Machine.TimerID {
        try XCTUnwrap(effects.compactMap { effect -> Machine.TimerID? in
            if case .schedule(let id, _) = effect { return id }
            return nil
        }.first, file: file, line: line)
    }
    private func longOutput(_ binding: KeyBinding) -> KeyBinding {
        var result = KeyBinding(action: .key, value: binding.longPressValue, modifiers: binding.longPressModifiers)
        result.rightModifiers = binding.longPressRightModifiers
        return result
    }

    func testImmediateKeyboardCapturesBindingAndIgnoresRepeatedEdges() {
        var machine = Machine()
        XCTAssertEqual(machine.press(.menu, binding: plain, context: context, now: 0), [.keyboard(plain, down: true)])
        XCTAssertTrue(machine.press(.menu, binding: segmented, context: context, now: 0.01).isEmpty)
        XCTAssertTrue(machine.isHolding)
        XCTAssertEqual(machine.release(.menu, now: 0.1), [.keyboard(plain, down: false)])
        XCTAssertFalse(machine.isHolding)
        XCTAssertTrue(machine.release(.menu, now: 0.11).isEmpty)
    }

    func testMouseRemainsHeldUntilMatchingReleaseOrReset() {
        var machine = Machine()
        let binding = KeyBinding(action: .click, value: "", mouseButton: .right)
        XCTAssertEqual(machine.press(.center, binding: binding, context: context, now: 0), [.mouse(.right, down: true, key: .center)])
        XCTAssertEqual(machine.heldMouseButtons, [.right])
        XCTAssertEqual(machine.reset(), [.mouse(.right, down: false, key: .center)])
        XCTAssertTrue(machine.heldMouseButtons.isEmpty)
        XCTAssertTrue(machine.reset().isEmpty)
        XCTAssertTrue(machine.release(.center, now: 1).isEmpty)
    }

    func testShortPressCancelsLongAndLateTimerCannotFireOnNextPress() throws {
        var machine = Machine()
        let first = try timer(machine.press(.voice, binding: long, context: context, now: 0))
        XCTAssertEqual(machine.release(.voice, now: 0.1), [.cancel(first), .tap(long, key: .voice)])
        let second = try timer(machine.press(.voice, binding: long, context: context, now: 0.2))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(machine.timerFired(first, now: 0.6).isEmpty)
        XCTAssertEqual(machine.timerFired(second, now: 0.6), [.keyboard(longOutput(long), down: true)])
        XCTAssertEqual(machine.release(.voice, now: 0.7), [.keyboard(longOutput(long), down: false)])
    }

    func testLongDeadlineDoesNotFireEarlyAndPreservesRightModifiers() throws {
        var machine = Machine()
        let id = try timer(machine.press(.voice, binding: long, context: context, now: 0))
        let early = machine.timerFired(id, now: 0.2)
        XCTAssertEqual(try timer(early), id)
        if case .schedule(_, let delay) = early.first { XCTAssertEqual(delay, 0.15, accuracy: 0.000001) }
        XCTAssertEqual(machine.timerFired(id, now: 0.35), [.keyboard(longOutput(long), down: true)])
        XCTAssertTrue(machine.timerFired(id, now: 0.4).isEmpty)
        XCTAssertEqual(machine.release(.voice, now: 0.5), [.keyboard(longOutput(long), down: false)])
    }

    func testBusySchedulerStillRecognizesLongAtRelease() throws {
        var machine = Machine()
        let id = try timer(machine.press(.voice, binding: long, context: context, now: 0))
        XCTAssertEqual(machine.release(.voice, now: 0.5), [
            .cancel(id), .keyboard(longOutput(long), down: true), .keyboard(longOutput(long), down: false)
        ])
        XCTAssertTrue(machine.timerFired(id, now: 0.6).isEmpty)
    }

    func testSilentHoldNeverFallsBackToSingleTap() throws {
        var machine = Machine()
        var binding = long; binding.holdNoOutput = true
        let id = try timer(machine.press(.voice, binding: binding, context: context, now: 0))
        XCTAssertTrue(machine.timerFired(id, now: 0.36).isEmpty)
        XCTAssertTrue(machine.release(.voice, now: 0.5).isEmpty)
        XCTAssertFalse(machine.hasPendingTap)
    }

    func testSegmentedDoubleCancelsSingleAndExecutesOnlyDouble() throws {
        var machine = Machine()
        XCTAssertTrue(machine.press(.voice, binding: segmented, context: context, now: 0).isEmpty)
        let id = try timer(machine.release(.voice, now: 0.01))
        XCTAssertTrue(machine.hasPendingTap)
        XCTAssertTrue(machine.press(.voice, binding: segmented, context: context, now: 0.05).isEmpty)
        XCTAssertEqual(machine.release(.voice, now: 0.10), [.cancel(id), .tap(.init(action: .key, value: "F6"), key: .voice)])
        XCTAssertTrue(machine.timerFired(id, now: 0.5).isEmpty)
        XCTAssertFalse(machine.hasPendingTap)
    }

    func testSingleTapWaitsForDoubleWindowAndRunsExactlyOnce() throws {
        var machine = Machine()
        _ = machine.press(.voice, binding: segmented, context: context, now: 0)
        let id = try timer(machine.release(.voice, now: 0.01))
        XCTAssertEqual(try timer(machine.timerFired(id, now: 0.1)), id)
        XCTAssertEqual(machine.timerFired(id, now: 0.22), [.tap(segmented, key: .voice)])
        XCTAssertTrue(machine.timerFired(id, now: 0.5).isEmpty)
        XCTAssertFalse(machine.hasPendingTap)
    }

    func testExpiredSingleFinishesBeforeNextPressEvenWhenCallbackIsLate() throws {
        var machine = Machine()
        _ = machine.press(.voice, binding: segmented, context: context, now: 0)
        let id = try timer(machine.release(.voice, now: 0.01))
        XCTAssertEqual(machine.press(.voice, binding: segmented, context: context, now: 0.3), [.cancel(id), .tap(segmented, key: .voice)])
        let second = try timer(machine.release(.voice, now: 0.31))
        XCTAssertEqual(machine.timerFired(second, now: 0.52), [.tap(segmented, key: .voice)])
        XCTAssertTrue(machine.timerFired(id, now: 0.6).isEmpty)
    }

    func testDifferentApplicationSceneOrBindingCannotCombineIntoDouble() throws {
        var otherApp = context; otherApp.application = "test.other"
        var otherScene = context; otherScene.scene = UUID()
        var otherBinding = segmented; otherBinding.doubleClickValue = "F8"
        for (nextContext, nextBinding) in [(otherApp, segmented), (otherScene, segmented), (context, otherBinding)] {
            var machine = Machine()
            _ = machine.press(.voice, binding: segmented, context: context, now: 0)
            let id = try timer(machine.release(.voice, now: 0.01))
            XCTAssertEqual(machine.press(.voice, binding: nextBinding, context: nextContext, now: 0.05), [.cancel(id), .tap(segmented, key: .voice)])
            let second = try timer(machine.release(.voice, now: 0.1))
            XCTAssertEqual(machine.timerFired(second, now: 0.31), [.tap(nextBinding, key: .voice)])
        }
    }

    func testSiriContinuousModeIsImmediateEvenWhenGestureFlagsAreEnabled() {
        var machine = Machine()
        var binding = segmented; binding.siriMode = "长按模式"; binding.longPressEnabled = true
        XCTAssertEqual(machine.press(.voice, binding: binding, context: context, now: 0), [.keyboard(binding, down: true)])
        XCTAssertEqual(machine.release(.voice, now: 0.01), [.keyboard(binding, down: false)])
        XCTAssertFalse(machine.hasPendingTap)
    }

    func testPowerDoubleActionsRetainExistingChoices() throws {
        for (choice, action) in [(PowerDoubleClickAction.sleepDisplay, XvicoAction.screenOff), (.lockScreen, .lockScreen), (.systemSleep, .systemSleep)] {
            var machine = Machine()
            let binding = KeyBinding(action: .screenOff, value: "", doubleClickEnabled: true, powerDoubleClickAction: choice)
            _ = machine.press(.power, binding: binding, context: context, now: 0)
            let id = try timer(machine.release(.power, now: 0.01))
            _ = machine.press(.power, binding: binding, context: context, now: 0.05)
            XCTAssertEqual(machine.release(.power, now: 0.1), [.cancel(id), .tap(.init(action: action, value: ""), key: .power)])
        }
    }

    func testRingToggleConsumesOnlySecondPairAndDoesNotCrossApplications() {
        var ringContext = context; ringContext.ringToggleKey = RemoteKey.menu.rawValue
        var machine = Machine()
        _ = machine.press(.menu, binding: plain, context: ringContext, now: 0)
        XCTAssertEqual(machine.release(.menu, now: 0.01), [.keyboard(plain, down: false)])
        XCTAssertEqual(machine.press(.menu, binding: plain, context: ringContext, now: 0.05), [.cycleRing])
        XCTAssertTrue(machine.press(.menu, binding: plain, context: ringContext, now: 0.06).isEmpty)
        XCTAssertTrue(machine.release(.menu, now: 0.1).isEmpty)
        _ = machine.press(.menu, binding: plain, context: ringContext, now: 0.12)
        _ = machine.release(.menu, now: 0.13)
        ringContext.application = "test.other"
        XCTAssertEqual(machine.press(.menu, binding: plain, context: ringContext, now: 0.15), [.keyboard(plain, down: true)])
    }

    func testSpecialVolumeAndDisabledKeysIgnoreDuplicateDownAndLateUp() {
        var machine = Machine()
        var special = context; special.volumeMode = .microphone
        XCTAssertEqual(machine.press(.volumeUp, binding: plain, context: special, now: 0), [.switchMicrophone(-1)])
        XCTAssertTrue(machine.press(.volumeUp, binding: plain, context: context, now: 0.01).isEmpty)
        XCTAssertTrue(machine.release(.volumeUp, now: 0.1).isEmpty)
        special.volumeMode = .scroll
        XCTAssertEqual(machine.press(.volumeDown, binding: plain, context: special, now: 0.2), [.scroll(-50)])
        XCTAssertTrue(machine.release(.volumeDown, now: 0.3).isEmpty)
        var disabled = plain; disabled.enabled = false
        XCTAssertEqual(machine.press(.menu, binding: disabled, context: context, now: 0.4), [.disabled(.menu)])
        XCTAssertTrue(machine.isHolding)
        XCTAssertTrue(machine.release(.menu, now: 0.5).isEmpty)
        XCTAssertTrue(machine.release(.menu, now: 0.6).isEmpty)
        XCTAssertFalse(machine.isHolding)
    }

    func testResetReleasesAllOwnedOutputAndInvalidatesPendingTimers() throws {
        var machine = Machine()
        _ = machine.press(.menu, binding: plain, context: context, now: 0)
        _ = machine.press(.voice, binding: segmented, context: context, now: 0)
        let single = try timer(machine.release(.voice, now: 0.01))
        let hold = try timer(machine.press(.playPause, binding: long, context: context, now: 0.05))
        let reset = machine.reset()
        XCTAssertEqual(reset.count, 3)
        XCTAssertTrue(reset.contains(.keyboard(plain, down: false)))
        XCTAssertTrue(reset.contains(.cancel(single)))
        XCTAssertTrue(reset.contains(.cancel(hold)))
        XCTAssertTrue(machine.timerFired(single, now: 1).isEmpty)
        XCTAssertTrue(machine.timerFired(hold, now: 1).isEmpty)
        let next = try timer(machine.press(.voice, binding: long, context: context, now: 1))
        XCTAssertNotEqual(next, hold)
        XCTAssertNotEqual(next, single)
    }
}
