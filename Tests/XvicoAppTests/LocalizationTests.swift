import XCTest
@testable import XvicoApp

final class LocalizationTests: XCTestCase {
    func testShippedBundlesResolveNewPageControlsInEachLanguage() throws {
        let keys = ["权限", "麦克风来源", "识别方式", "输入法触发键", "界面外观", "语音命令", "预设库", "遥控器输入源"]
        for language in ["en", "ja", "fr"] {
            let table = try XCTUnwrap(XvicoLocalization.tables[language])
            for key in keys {
                let result = XvicoLocalization.string(key, locale: Locale(identifier: language))
                XCTAssertEqual(result, try XCTUnwrap(table[key]))
                XCTAssertNotEqual(result, key, "\(language) must not fall back to Chinese for \(key)")
            }
        }
        XCTAssertEqual(XvicoLocalization.string("麦克风来源", locale: Locale(identifier: "zh-Hans")), "麦克风来源")
    }

    func testRuntimeStatusInterpolationsTranslateActionsAndKeepNumbers() {
        let locale = Locale(identifier: "en")
        XCTAssertEqual(XvicoLocalization.string("当前实际动作：滚轮（全局）", locale: locale), "Current action: Scrolling (Global)")
        XCTAssertEqual(XvicoLocalization.string("麦克风已关闭；执行 Fn 映射可开始语音输入。", locale: locale),
                       "Microphone is off; send the Fn mapping to start voice input.")
        XCTAssertEqual(XvicoLocalization.string("ChatGPT 当前使用「Coding」场景：滚轮", locale: locale),
                       "ChatGPT uses the “Coding” scene: Scrolling")
    }

    func testLocalizedPrefixesPreserveUnknownUserTextAndUnsupportedSystemLanguageFallsBackToEnglish() {
        let locale = Locale(identifier: "fr")
        XCTAssertEqual(XvicoLocalization.string("系统输入：My Custom Mic", locale: locale), "Entrée système : My Custom Mic")
        XCTAssertEqual(XvicoLocalization.string("用户自定义内容 XYZ", locale: locale), "用户自定义内容 XYZ")
        XCTAssertEqual(XvicoLocalization.string("权限", locale: Locale(identifier: "de-DE")), "Permissions")
        XCTAssertEqual(XvicoLocalization.string("权限", locale: Locale(identifier: "zh-TW")), "权限")
    }
}
