import Foundation
import SwiftUI
import Combine

enum MacTheme: String, CaseIterable, Identifiable, Codable {
    case green
    case pink
    case cyan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green: return "绿色"
        case .pink: return "粉色"
        case .cyan: return "青色"
        }
    }
}

/// 用户偏好与隐私设置，基于 UserDefaults 持久化。
///
/// - seealso: PRD v0.2 5.6（新建模式持久记忆）、11.5（隐私保护）
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    static let macEditorFontSizeRange: ClosedRange<Double> = 12...18
    static let macEditorFontSizeStep: Double = 1
    static let defaultMacEditorFontSize: Double = 14
    static let defaultMacEditorLineHeightMultiple: Double = 1.25
    static let macEditorLineHeightRange: ClosedRange<Double> = 1.2...2.0
    static let defaultMacTheme: MacTheme = .green
    static let macThemeDefaultsKey = "BKMacTheme"

    private let defaults: UserDefaults

    @Published var preferredNoteMode: NoteMode {
        didSet { defaults.set(preferredNoteMode.rawValue, forKey: Keys.preferredNoteMode) }
    }

    @Published var hideContentOnBackground: Bool {
        didSet { defaults.set(hideContentOnBackground, forKey: Keys.hideContentOnBackground) }
    }

    @Published var autoUnloadKeyOnForeground: Bool {
        didSet { defaults.set(autoUnloadKeyOnForeground, forKey: Keys.autoUnloadKeyOnForeground) }
    }

    @Published var hasSeenFirstKeyPrompt: Bool {
        didSet { defaults.set(hasSeenFirstKeyPrompt, forKey: Keys.hasSeenFirstKeyPrompt) }
    }

    @Published var hasSeededDefaultNotes: Bool {
        didSet { defaults.set(hasSeededDefaultNotes, forKey: Keys.hasSeededDefaultNotes) }
    }

    @Published var macEditorFontSize: Double {
        didSet {
            let clamped = Self.clampedFontSize(macEditorFontSize)
            if macEditorFontSize != clamped {
                macEditorFontSize = clamped
                return
            }
            defaults.set(macEditorFontSize, forKey: Keys.macEditorFontSize)
        }
    }

    @Published var macEditorLineHeightMultiple: Double {
        didSet {
            let clamped = Self.clampedLineHeightMultiple(macEditorLineHeightMultiple)
            if macEditorLineHeightMultiple != clamped {
                macEditorLineHeightMultiple = clamped
                return
            }
            defaults.set(macEditorLineHeightMultiple, forKey: Keys.macEditorLineHeightMultiple)
        }
    }

    @Published var copyAddsParagraphSpacing: Bool {
        didSet { defaults.set(copyAddsParagraphSpacing, forKey: Keys.copyAddsParagraphSpacing) }
    }

    @Published var autoDeleteEmptyNotes: Bool {
        didSet { defaults.set(autoDeleteEmptyNotes, forKey: Keys.autoDeleteEmptyNotes) }
    }

    @Published var macTheme: MacTheme {
        didSet { defaults.set(macTheme.rawValue, forKey: Self.macThemeDefaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferredNoteMode = NoteMode(rawValue: defaults.string(forKey: Keys.preferredNoteMode) ?? "") ?? .plain
        self.hideContentOnBackground = defaults.object(forKey: Keys.hideContentOnBackground) as? Bool ?? true
        self.autoUnloadKeyOnForeground = defaults.object(forKey: Keys.autoUnloadKeyOnForeground) as? Bool ?? false
        self.hasSeenFirstKeyPrompt = defaults.bool(forKey: Keys.hasSeenFirstKeyPrompt)
        self.hasSeededDefaultNotes = defaults.bool(forKey: Keys.hasSeededDefaultNotes)

        let storedFontSize = defaults.double(forKey: Keys.macEditorFontSize)
        if storedFontSize > 0 {
            self.macEditorFontSize = Self.clampedFontSize(storedFontSize)
        } else {
            self.macEditorFontSize = Self.defaultMacEditorFontSize
        }

        let storedLineHeight = defaults.double(forKey: Keys.macEditorLineHeightMultiple)
        if storedLineHeight > 0 {
            self.macEditorLineHeightMultiple = Self.clampedLineHeightMultiple(storedLineHeight)
        } else {
            self.macEditorLineHeightMultiple = Self.defaultMacEditorLineHeightMultiple
        }

        self.copyAddsParagraphSpacing = defaults.object(forKey: Keys.copyAddsParagraphSpacing) as? Bool ?? false
        self.autoDeleteEmptyNotes = defaults.object(forKey: Keys.autoDeleteEmptyNotes) as? Bool ?? true
        self.macTheme = MacTheme(rawValue: defaults.string(forKey: Self.macThemeDefaultsKey) ?? "") ?? Self.defaultMacTheme
    }

    /// 用于测试：重置为默认值。
    func resetForTesting() {
        preferredNoteMode = .plain
        hideContentOnBackground = true
        autoUnloadKeyOnForeground = false
        hasSeenFirstKeyPrompt = false
        hasSeededDefaultNotes = false
        macEditorFontSize = Self.defaultMacEditorFontSize
        macEditorLineHeightMultiple = Self.defaultMacEditorLineHeightMultiple
        copyAddsParagraphSpacing = false
        autoDeleteEmptyNotes = true
        macTheme = Self.defaultMacTheme
    }

    static func clampedFontSize(_ value: Double) -> Double {
        min(max(value.rounded(), macEditorFontSizeRange.lowerBound), macEditorFontSizeRange.upperBound)
    }

    static func clampedLineHeightMultiple(_ value: Double) -> Double {
        min(max(value, macEditorLineHeightRange.lowerBound), macEditorLineHeightRange.upperBound)
    }

    private enum Keys {
        static let preferredNoteMode = "BKPreferredNoteMode"
        static let hideContentOnBackground = "BKHideContentOnBackground"
        static let autoUnloadKeyOnForeground = "BKAutoUnloadKeyOnForeground"
        static let hasSeenFirstKeyPrompt = "BKHasSeenFirstKeyPrompt"
        static let hasSeededDefaultNotes = "BKHasSeededDefaultNotes"
        static let macEditorFontSize = "BKMacEditorFontSize"
        static let macEditorLineHeightMultiple = "BKMacEditorLineHeightMultiple"
        static let copyAddsParagraphSpacing = "BKCopyAddsParagraphSpacing"
        static let autoDeleteEmptyNotes = "BKAutoDeleteEmptyNotes"
    }
}
