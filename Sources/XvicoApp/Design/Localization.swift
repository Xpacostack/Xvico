import SwiftUI
import Foundation

enum XvicoLocalization {
    private static let placeholders = try! NSRegularExpression(pattern: #"%(?:[1-9]\d*\$)?[-+0-9.]*(?:ll|l)?[@diufgGxX]"#)
    private struct Template {
        let expression: NSRegularExpression
        let translation: String
        let specificity: Int
    }
    static let tables: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for language in ["zh-Hans", "en", "ja", "fr"] {
            guard let folder = Bundle.module.url(forResource: language, withExtension: "lproj"),
                  let table = NSDictionary(contentsOf: folder.appendingPathComponent("Localizable.strings")) as? [String: String] else { continue }
            result[language] = table
        }
        return result
    }()
    private static let templates: [String: [Template]] = tables.mapValues { table in
        table.compactMap { key, translation in
            let range = NSRange(key.startIndex..., in: key)
            let matches = placeholders.matches(in: key, range: range)
            guard !matches.isEmpty else { return nil }
            let source = key as NSString
            var pattern = "^", cursor = 0, literalLength = 0
            for match in matches {
                let literal = source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                literalLength += literal.utf16.count
                pattern += NSRegularExpression.escapedPattern(for: literal) + "(.+?)"
                cursor = NSMaxRange(match.range)
            }
            let last = source.substring(from: cursor)
            pattern += NSRegularExpression.escapedPattern(for: last) + "$"
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
            return Template(expression: expression, translation: translation, specificity: literalLength + last.utf16.count)
        }.sorted { $0.specificity > $1.specificity }
    }

    static func language(for locale: Locale) -> String {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("zh") { return "zh-Hans" }
        if identifier.hasPrefix("ja") { return "ja" }
        if identifier.hasPrefix("fr") { return "fr" }
        return "en"
    }

    static func string(_ source: String, locale: Locale) -> String {
        resolve(source, language: language(for: locale), depth: 0)
    }

    private static func resolve(_ source: String, language: String, depth: Int) -> String {
        guard let table = tables[language] else { return source }
        if let translated = table[source] { return translated }
        guard depth < 3, source.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil else { return source }
        let range = NSRange(source.startIndex..., in: source)
        for template in templates[language] ?? [] {
            guard let match = template.expression.firstMatch(in: source, range: range), match.range == range else { continue }
            let original = source as NSString
            let arguments = (1..<match.numberOfRanges).map {
                resolve(original.substring(with: match.range(at: $0)), language: language, depth: depth + 1)
            }
            let translation = template.translation as NSString
            let tokens = placeholders.matches(in: template.translation, range: NSRange(location: 0, length: translation.length))
            var result = "", cursor = 0
            for (index, token) in tokens.enumerated() {
                result += translation.substring(with: NSRange(location: cursor, length: token.range.location - cursor))
                let format = translation.substring(with: token.range)
                let position = format.dropFirst().split(separator: "$", maxSplits: 1)
                let argumentIndex = position.count == 2 ? (Int(position[0]) ?? (index + 1)) - 1 : index
                guard arguments.indices.contains(argumentIndex) else { return source }
                result += arguments[argumentIndex]
                cursor = NSMaxRange(token.range)
            }
            result += translation.substring(from: cursor)
            return result
        }
        for prefix in ["系统输入：", "麦克风：", "运行失败：", "快捷键 "] where source.hasPrefix(prefix) {
            return (table[prefix] ?? prefix) + source.dropFirst(prefix.count)
        }
        return source
    }
}

struct XvicoLocalizedText: View {
    @Environment(\.locale) private var locale
    let source: String
    init(_ source: String) { self.source = source }
    var body: some View {
        Text(verbatim: XvicoLocalization.string(source, locale: locale))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct XvicoLocalizedLabel: View {
    let source: String
    let systemImage: String
    init(_ source: String, systemImage: String) { self.source = source; self.systemImage = systemImage }
    var body: some View {
        Label { XvicoLocalizedText(source) } icon: { Image(systemName: systemImage) }
    }
}

private struct XvicoPresentationSettings: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @AppStorage("xvibe.appearance") private var appearance = XvicoAppearance.system.rawValue

    func body(content: Content) -> some View {
        content
            .environment(\.locale, model.interfaceLocale)
            .preferredColorScheme((XvicoAppearance(rawValue: appearance) ?? .system).colorScheme)
            .tint(.blue)
            .environment(\.xvicoImmersiveGlass, true)
    }
}

extension AppModel {
    var interfaceLocale: Locale {
        let chosen = settings.interfaceLanguage.localeIdentifier.map(Locale.init(identifier:)) ?? .current
        return Locale(identifier: XvicoLocalization.language(for: chosen))
    }
}

extension View {
    // macOS presentations may create a separate hosting environment.
    // Apply the user's language and appearance at every presented root.
    func xvicoPresentationSettings() -> some View {
        modifier(XvicoPresentationSettings())
    }
}
