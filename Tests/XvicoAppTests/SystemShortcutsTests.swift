import XCTest
@testable import XvicoApp

private actor TestShortcutRunner: ShortcutCommandRunning {
    let result: ShortcutCommandResult
    private(set) var calls: [[String]] = []
    init(_ result: ShortcutCommandResult) { self.result = result }
    func execute(_ arguments: [String]) async throws -> ShortcutCommandResult { calls.append(arguments); return result }
}

@MainActor
final class SystemShortcutsTests: XCTestCase {
    func testNativeCallbacksEncodeNamesAndRejectForeignCompletion() async throws {
        let shortcut = SystemShortcut(id: UUID(), name: "中文 & (QA)")
        var opened: URL?
        let service = SystemShortcutsService(urlOpener: { opened = $0; return true })
        await service.run(shortcut)
        XCTAssertEqual(service.runningID, shortcut.id)
        let components = URLComponents(url: try XCTUnwrap(opened), resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "name" })?.value, shortcut.name)
        XCTAssertFalse(service.handleCallback(URL(string: "xvibe://shortcut/success?token=foreign")!))
        let callback = components.queryItems!.first(where: { $0.name == "x-success" })!.value!
        XCTAssertTrue(service.handleCallback(URL(string: callback)!))
        XCTAssertNil(service.runningID)
        XCTAssertEqual(service.message, "已运行：" + shortcut.name)
        XCTAssertFalse(service.handleCallback(URL(string: callback)!))
    }
    func testNativeCallbackCancellationAndFailureDoNotReportSuccess() async throws {
        let shortcut = SystemShortcut(id: UUID(), name: "QA")
        var opened: URL?
        let service = SystemShortcutsService(urlOpener: { opened = $0; return true })
        await service.run(shortcut)
        let components = URLComponents(url: try XCTUnwrap(opened), resolvingAgainstBaseURL: false)!
        let callback = components.queryItems!.first(where: { $0.name == "x-cancel" })!.value!
        XCTAssertTrue(service.handleCallback(URL(string: callback)!))
        XCTAssertEqual(service.message, "已取消：QA")
        XCTAssertNil(service.runningID)
        await service.run(shortcut)
        service.stopWaiting()
        XCTAssertFalse(service.handleCallback(URL(string: callback)!))
        let rejected = SystemShortcutsService(urlOpener: { _ in false })
        await rejected.run(shortcut)
        XCTAssertNil(rejected.runningID)
        XCTAssertNotNil(rejected.errorMessage)
    }
    func testListParsingPreservesUnicodeAndParenthesizedNames() async throws {
        let text = "中文名称 (inner) (503694FD-E560-49BF-8DDA-BB0A7422AEEC)\ninvalid\n中文名称 (inner) (503694FD-E560-49BF-8DDA-BB0A7422AEEC)"
        let values = SystemShortcutsService.parse(text)
        XCTAssertEqual(values.count, 1); XCTAssertEqual(values[0].name, "中文名称 (inner)")
    }
    func testRefreshAndRunUseStableIdentifierWithoutShell() async throws {
        let runner = TestShortcutRunner(.init(status: 0, output: "Example (503694FD-E560-49BF-8DDA-BB0A7422AEEC)"))
        let service = SystemShortcutsService(runner: runner, executionMode: .command)
        await service.refresh()
        XCTAssertEqual(service.shortcuts.count, 1)
        await service.run(service.shortcuts[0])
        let calls = await runner.calls
        XCTAssertEqual(calls, [["list", "--show-identifiers"], ["run", "503694FD-E560-49BF-8DDA-BB0A7422AEEC"]])
        XCTAssertNil(service.runningID); XCTAssertNil(service.errorMessage)
        XCTAssertEqual(service.message, "已运行：Example")
    }
    func testErrorsAreReportedInsteadOfSuccess() async throws {
        let service = SystemShortcutsService(runner: TestShortcutRunner(.init(status: 1, output: "Test failure")), executionMode: .command)
        await service.refresh()
        XCTAssertTrue(service.shortcuts.isEmpty); XCTAssertFalse(service.refreshing)
        XCTAssertTrue(service.errorMessage?.contains("Test failure") == true)
        await service.run(.init(id: UUID(), name: "Example"))
        XCTAssertNil(service.message); XCTAssertNil(service.runningID)
        XCTAssertTrue(service.errorMessage?.contains("运行失败") == true)
    }
}
