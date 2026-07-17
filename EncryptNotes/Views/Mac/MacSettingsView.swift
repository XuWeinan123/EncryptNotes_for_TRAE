import Foundation
import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class MacSettingsRouter: ObservableObject {
    static let shared = MacSettingsRouter()

    @Published var selectedTab: MacSettingsView.Tab = .general

    private init() {}
}

struct MacSettingsView: View {
    enum Tab: Hashable {
        case general
        case editor
        case shortcuts
        case key
        case about
    }

    @ObservedObject private var shortcutStore = ShortcutStore.shared
    @ObservedObject private var vaultStore = VaultStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var localSelectedTab: Tab
    private let externalSelectedTab: Binding<Tab>?
    @State private var recordingAction: MacShortcutRecordingAction?
    @State private var settingsErrorMessage: String?
    #if DEBUG
    @State private var isShowingRestoreDefaultsConfirmation = false
    #endif

    init(selectedTab: Tab = .general) {
        _localSelectedTab = State(initialValue: selectedTab)
        externalSelectedTab = nil
    }

    init(selectedTab: Binding<Tab>) {
        _localSelectedTab = State(initialValue: selectedTab.wrappedValue)
        externalSelectedTab = selectedTab
    }

    private var selectedTab: Binding<Tab> {
        externalSelectedTab ?? $localSelectedTab
    }

    var body: some View {
        TabView(selection: selectedTab) {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tab.general)

            editorTab
                .tabItem {
                    Label("Editor", systemImage: "textformat")
                }
                .tag(Tab.editor)

            shortcutTab
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(Tab.shortcuts)

            keyTab
                .tabItem {
                    Label("Key", systemImage: "key")
                }
                .tag(Tab.key)

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(Tab.about)
        }
        .padding(.horizontal, DS.s4)
        .padding(.bottom, DS.s4)
        .frame(
            minWidth: 640,
            idealWidth: 640,
            maxWidth: 640,
            minHeight: 660,
            idealHeight: 660,
            maxHeight: 660
        )
        .background(DS.bg)
        .background(shortcutRecorder)
        .alert("Settings Failed", isPresented: settingsErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(settingsErrorMessage ?? L10n.string("This setting could not be saved."))
        }
        #if DEBUG
        .confirmationDialog(
            "Restore All Default Settings?",
            isPresented: $isShowingRestoreDefaultsConfirmation
        ) {
            Button("Restore All Defaults", role: .destructive) {
                restoreAllDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This restores all settings, shortcuts, and the launch introduction without deleting notes or keys.")
        }
        #endif
    }

    private var generalTab: some View {
        panelStack {
            macPanel("Language") {
                SWSettingsRow("Application Language", systemImage: "globe") {
                    Picker("Application Language", selection: $settings.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.titleKey).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190, alignment: .trailing)
                }
            }

            macPanel("Menu Bar") {
                toggleRow("Launch Menu Bar App at Login", systemImage: "menubar.rectangle", isOn: launchAtLoginBinding)

                SWRowDivider()

                SWSettingsRow("Number of Recent Notes", systemImage: "list.number") {
                    Picker("Number of Recent Notes", selection: recentNotesLimitBinding) {
                        ForEach(SettingsStore.macRecentNotesLimitOptions, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .tint(DS.primary)
                }
            }

            macPanel("Notes") {
                toggleRow("Pin New Notes by Default", systemImage: "pin.fill", isOn: $settings.pinNewNotesByDefault)
                SWRowDivider()
                toggleRow("Encrypt New Notes Automatically", subtitle: vaultStore.isKeyLoaded ? nil : "Create or load a key in Key Settings first.", systemImage: "lock", isOn: newEncryptedNoteBinding)
                    .disabled(!vaultStore.isKeyLoaded)
            }

            macPanel("Storage") {
                SWSettingsRow(
                    vaultStore.isUsingICloudStorage ? "iCloud Folder" : "Local Folder",
                    subtitle: vaultStore.isUsingICloudStorage ? "Note files are stored directly in a public iCloud Drive folder." : "iCloud is unavailable, so local storage is being used.",
                    systemImage: vaultStore.isUsingICloudStorage ? "icloud" : "folder",
                    tint: vaultStore.isUsingICloudStorage ? DS.primaryDeep : DS.warning,
                    trailingMinWidth: 72
                ) {
                    Button("Open") {
                        openStorageFolder()
                    }
                    .settingsFilledButton()
                }
            }

            macPanel("Theme") {
                SWSettingsRow("Theme Color", systemImage: "paintpalette", tint: DS.primaryDeep) {
                    Picker("Theme Color", selection: $settings.macTheme) {
                        ForEach(MacTheme.allCases) { theme in
                            Text(LocalizedStringKey(theme.title)).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .tint(DS.primary)
                }
            }
        }
    }

    private var aboutTab: some View {
        panelStack {
            SWSectionPanel {
                VStack(spacing: DS.s8){
                    VStack(spacing: DS.s6) {
                        aboutLogo
                        
                        VStack(spacing: DS.s2) {
                            Text("Seal Note")
                                .font(DS.display())
                                .foregroundStyle(DS.textEmphasize)
                            
                            Text("v\(appVersion)")
                                .font(DS.caption())
                                .foregroundStyle(DS.textSubtle)
                            
                            Text("Capture quickly without interrupting your work.")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(DS.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    HStack(alignment: .top, spacing: DS.s6) {
                        feature(
                            systemImage: "menubar.rectangle",
                            title: "Quick Capture",
                            detail: "Create or open recent notes from the menu bar without interrupting your work."
                        )
                        
                        feature(
                            systemImage: "doc.plaintext",
                            title: "Portable by Design",
                            detail: "Save as standard Markdown files for easy sync, migration, and use across tools."
                        )
                        
                        feature(
                            systemImage: "lock.shield",
                            title: "On-Device Encryption",
                            detail: "On-device encryption with a key file you own and manage."
                        )
                    }
                    .padding(.horizontal, DS.s6)
                }
                .padding(.vertical, DS.s8)
            }

            macPanel("Components") {
                SWSettingsRow("View Components", systemImage: "square.grid.2x2") {
                    Button {
                        MacMenuBarController.shared.openComponentCatalogWindow()
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.body)
                    }
                    .settingsFilledButton()
                    .help("Open Component Catalog")
                }
            }

            macPanel("Maintenance Log") {
                SWSettingsRow("Enable Logging", subtitle: "Record save and index metadata without recording note content or keys.", systemImage: "doc.text.magnifyingglass") {
                    if settings.maintenanceLoggingEnabled {
                        HStack(spacing: DS.s2) {
                            Button {
                                openMaintenanceLogFolder()
                            } label: {
                                Image(systemName: "folder")
                            }
                            .settingsFilledButton()
                            .help("Open Log Folder")

                            Button("Close", role: .destructive) {
                                settings.maintenanceLoggingEnabled = false
                            }
                            .settingsDestructiveFilledButton()
                        }
                    } else {
                        Button("Enable") {
                            settings.maintenanceLoggingEnabled = true
                        }
                        .settingsFilledButton()
                    }
                }
            }

            HStack(spacing: DS.s3) {
                Link("Privacy Policy", destination: privacyPolicyURL)
                #if DEBUG
                Text("·")
                    .foregroundStyle(DS.textSubtle)
                Button("Restore All Defaults") {
                    isShowingRestoreDefaultsConfirmation = true
                }
                .buttonStyle(.link)
                #endif
            }
            .font(DS.caption())
            .frame(maxWidth: .infinity, alignment: .center)
        
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var privacyPolicyURL: URL {
        URL(string: "https://github.com/XuWeinan123/EncryptNotes_for_TRAE/blob/main/PRIVACY.md")!
    }

    #if DEBUG
    private func restoreAllDefaults() {
        do {
            try settings.restoreAllDefaults()
            shortcutStore.resetAllShortcuts()
            MacMenuBarController.shared.restoreDefaultWindowSizes()
        } catch {
            settingsErrorMessage = L10n.string("Could not restore all default settings: %@", error.localizedDescription)
        }
    }
    #endif
    
    private func feature(systemImage: String, title: String, detail: String) -> some View {
        VStack(spacing: DS.s2) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.primaryDeep)
                .frame(width: 32, height: 32)
                .background(DS.primaryContainer)
                .clipShape(Circle())

            Text(LocalizedStringKey(title))
                .font(DS.bodyLg().weight(.semibold))
                .foregroundStyle(DS.textStrong)
                .multilineTextAlignment(.center)

            Text(LocalizedStringKey(detail))
                .font(DS.caption())
                .foregroundStyle(DS.textSubtle)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var editorTab: some View {
        panelStack {
            macPanel("Editing Experience") {
                SWSettingsRow("Editor Font Size", systemImage: "textformat.size") {
                    VStack(alignment: .trailing, spacing: DS.s1) {
                        Text(String(format: "%.0f", settings.macEditorFontSize))
                            .font(DS.caption())
                            .foregroundColor(DS.textSecondary)
                            .monospacedDigit()
                        Slider(
                            value: fontSizeBinding,
                            in: SettingsStore.macEditorFontSizeRange,
                            step: SettingsStore.macEditorFontSizeStep
                        )
                        .frame(width: 150)
                        .tint(DS.primary)
                    }
                }

                SWRowDivider()

                SWSettingsRow("Line Height", systemImage: "line.3.horizontal.decrease") {
                    VStack(alignment: .trailing, spacing: DS.s1) {
                        Text(String(format: "%.2fx", settings.macEditorLineHeightMultiple))
                            .font(DS.caption())
                            .foregroundColor(DS.textSecondary)
                            .monospacedDigit()
                        Slider(
                            value: lineHeightBinding,
                            in: SettingsStore.macEditorLineHeightRange,
                            step: 0.05
                        )
                        .frame(width: 150)
                        .tint(DS.primary)
                    }
                }
            }

            macPanel("Editing Behavior") {
                toggleRow("Copy as Looser Markdown Paragraphs", subtitle: "Automatically add blank lines between paragraphs when copying for Markdown editors such as Typora.", systemImage: "doc.on.clipboard", isOn: $settings.copyAddsParagraphSpacing)

                SWRowDivider()

                toggleRow("Discard Empty Notes When Closing", systemImage: "trash", isOn: $settings.autoDeleteEmptyNotes)

                SWRowDivider()

                toggleRow("Name Notes Automatically", subtitle: "When enabled, every autosave renames the note from its content. When disabled, manual titles and the initial title rule are preserved.", systemImage: "text.cursor", isOn: $settings.autoRenameNotesOnSave)

                SWRowDivider()

                toggleRow("Exclude Hex Colors from Tags", subtitle: "Ignore #RRGGBB and #RRGGBBAA color values.", systemImage: "paintpalette", isOn: $settings.excludeHexColorsFromTags)
            }
        }
    }


    private var shortcutTab: some View {
        panelStack {
            macPanel("Common Actions") {
                LazyVGrid(columns: shortcutGridColumns, alignment: .leading, spacing: DS.s2) {
                    shortcutTile(
                        title: "New Note",
                        value: ShortcutStore.displayStringForKey(
                            keyCode: shortcutStore.newNoteKey.keyCode,
                            modifiers: shortcutStore.newNoteKey.modifiers
                        ),
                        isRecording: recordingAction == .newNote,
                        onRecord: { recordingAction = .newNote }
                    )

                    ForEach(EditorShortcutAction.allCases) { action in
                        let shortcut = shortcutStore.shortcut(for: action)
                        shortcutTile(
                            title: action.title,
                            value: ShortcutStore.displayStringForKey(
                                keyCode: shortcut.keyCode,
                                modifiers: shortcut.modifiers
                            ),
                            isRecording: recordingAction == .editor(action),
                            onRecord: { recordingAction = .editor(action) }
                        )
                    }
                }
            }

            macPanel("Markdown Formatting") {
                LazyVGrid(columns: shortcutGridColumns, alignment: .leading, spacing: DS.s2) {
                    ForEach(MarkdownShortcutAction.allCases) { action in
                        let shortcut = shortcutStore.shortcut(for: action)
                        shortcutTile(
                            title: action.title,
                            value: ShortcutStore.displayStringForKey(
                                keyCode: shortcut.keyCode,
                                modifiers: shortcut.modifiers
                            ),
                            isRecording: recordingAction == .markdown(action),
                            onRecord: { recordingAction = .markdown(action) }
                        )
                    }
                }

            }

            HStack(spacing: DS.s2) {
                helperText(recordingAction == nil ? "Click record, then press a new key combination. Press Esc to cancel." : "Recording: press a new key combination, or press Esc to cancel.")
                Spacer(minLength: DS.s3)
                Button("Restore Defaults") {
                    shortcutStore.resetAllShortcuts()
                    recordingAction = nil
                }
                .settingsFilledButton()
            }
        }
    }

    private var keyTab: some View {
        panelStack {
            let keyStatus = vaultStore.macKeyStatus
            macPanel("Key Status") {
                SWSettingsRow(
                    keyStatusTitle(keyStatus),
                    subtitle: keyManagementSubtitle(for: keyStatus),
                    systemImage: keyManagementIcon(for: keyStatus),
                    tint: keyManagementTint(for: keyStatus)
                ) {
                    keyManagementActions(for: keyStatus)
                }
            }
        }
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { settings.macEditorFontSize },
            set: { newValue in
                settings.macEditorFontSize = newValue
            }
        )
    }

    private func keyStatusTitle(_ status: MacVaultKeyStatus) -> String {
        switch status {
        case .noReference:
            return "No Key Loaded"
        case .available:
            return "Key Loaded"
        case .invalid(.keyReplaced):
            return "Key Replaced"
        case .invalid(.keyDownloadPending):
            return "Key Downloading"
        case .invalid:
            return "Key Invalid"
        }
    }

    private func keyStatusSubtitle(_ status: MacVaultKeyStatus) -> String {
        switch status {
        case .noReference:
            return "Load the key to view encrypted note content"
        case .available:
            return "This Mac can unlock encrypted notes"
        case .invalid(.keyDownloadPending):
            return "The key file is still downloading from iCloud. Try again later."
        case .invalid:
            return "Relocate the key before encrypted notes can be unlocked"
        }
    }

    private func keyManagementSubtitle(for status: MacVaultKeyStatus) -> String {
        let encryptedCount = vaultStore.encryptedEntryCount
        switch status {
        case .noReference where encryptedCount > 0:
            return L10n.string("%lld encrypted notes were found. Load the original key first.", Int64(encryptedCount))
        case .noReference:
            return "No key is currently loaded. Seal Note reads key files only on this Mac and does not save them to Keychain."
        case .available:
            return abbreviatedDisplayPath(vaultStore.keyFileDisplayPath)
                ?? "Keep the key safe. Encrypted notes cannot be recovered if it is lost."
        case .invalid(.keyDownloadPending):
            return "The key file has been requested from iCloud. Open encrypted notes after the download finishes."
        case .invalid where encryptedCount > 0:
            return L10n.string("The key is invalid. %lld encrypted notes require the original key.", Int64(encryptedCount))
        case .invalid:
            return "The key is unavailable, invalid, or has been replaced."
        }
    }

    private func abbreviatedDisplayPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let cloudDocsPath = "/Library/Mobile Documents/com~apple~CloudDocs"
        guard let cloudDocsRange = standardizedPath.range(of: cloudDocsPath) else {
            return standardizedPath
        }

        let relativePath = standardizedPath[cloudDocsRange.upperBound...]
        guard relativePath.isEmpty || relativePath.hasPrefix("/") else {
            return standardizedPath
        }
        return "iCloud Drive" + relativePath
    }

    private func keyManagementIcon(for status: MacVaultKeyStatus) -> String {
        switch status {
        case .noReference:
            return "lock.shield"
        case .available:
            return "checkmark.shield.fill"
        case .invalid:
            return "exclamationmark.triangle"
        }
    }

    private func keyManagementTint(for status: MacVaultKeyStatus) -> Color {
        switch status {
        case .noReference:
            return DS.textSubtle
        case .available:
            return DS.primaryDeep
        case .invalid:
            return DS.destructive
        }
    }

    @ViewBuilder
    private func keyManagementActions(for status: MacVaultKeyStatus) -> some View {
        switch status {
        case .noReference:
            if vaultStore.encryptedEntryCount > 0 {
                HStack(spacing: DS.s2) {
                    Button("Load Existing Key") {
                        loadKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(DS.primary)

                    Button("Create New Key") {
                        createNewKey()
                    }
                    .settingsFilledButton()
                }
            } else {
                HStack(spacing: DS.s2) {
                    Button("Create New Key") {
                        createNewKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(DS.primary)

                    Button("Load Existing Key") {
                        loadKey()
                    }
                    .settingsFilledButton()
                }
            }
        case .available:
            HStack(spacing: DS.s2) {
                Button {
                    openKeyLocation()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Open Key Location")

                Button("Remove", role: .destructive) {
                    unloadKey()
                }
                .settingsFilledButton()
            }
        case .invalid:
            HStack(spacing: DS.s2) {
                Button("Relocate Key") {
                    loadKey()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(DS.primary)

                Button("Remove", role: .destructive) {
                    unloadKey()
                }
                .settingsFilledButton()
            }
        }
    }

    private var lineHeightBinding: Binding<Double> {
        Binding(
            get: { settings.macEditorLineHeightMultiple },
            set: { settings.macEditorLineHeightMultiple = $0 }
        )
    }

    private var newEncryptedNoteBinding: Binding<Bool> {
        Binding(
            get: { settings.preferredNoteMode == .encrypted },
            set: { isOn in
                settings.preferredNoteMode = isOn && vaultStore.isKeyLoaded ? .encrypted : .plain
            }
        )
    }

    private var recentNotesLimitBinding: Binding<Int> {
        Binding(
            get: { settings.macRecentNotesLimit },
            set: { settings.macRecentNotesLimit = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { isEnabled in
                do {
                    try settings.setLaunchAtLogin(isEnabled)
                } catch {
                    settingsErrorMessage = L10n.string("Could not update the login item setting: %@", error.localizedDescription)
                }
            }
        )
    }

    private var settingsErrorBinding: Binding<Bool> {
        Binding(
            get: { settingsErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    settingsErrorMessage = nil
                }
            }
        )
    }

    private var shortcutRecorder: some View {
        ShortcutRecorderView(recordingAction: $recordingAction) { action, shortcut in
            switch action {
            case .newNote:
                shortcutStore.setNewNoteShortcut(shortcut)
            case .markdown(let markdownAction):
                shortcutStore.setMarkdownShortcut(shortcut, for: markdownAction)
            case .editor(let editorAction):
                shortcutStore.setEditorShortcut(shortcut, for: editorAction)
            }
            recordingAction = nil
        }
        .frame(width: 0, height: 0)
    }

    private var shortcutGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: DS.s2),
            GridItem(.flexible(), spacing: DS.s2)
        ]
    }

    private func panelStack<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        MacSettingsPage(content: content)
    }

    private func macPanel<Content: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        SWSectionPanel {
            VStack(alignment: .leading, spacing: DS.s2) {
                content()
            }
            .padding(.horizontal, DS.s3)
            .padding(.vertical, DS.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleRow(_ title: String, subtitle: String? = nil, systemImage: String? = nil, isOn: Binding<Bool>) -> some View {
        SWSettingsRow(
            title,
            subtitle: subtitle,
            systemImage: systemImage ?? (isOn.wrappedValue ? "checkmark.circle.fill" : "circle"),
            trailingMinWidth: 72
        ) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DS.primary)
        }
    }

    private func shortcutTile(title: String, value: String, isRecording: Bool, onRecord: @escaping () -> Void) -> some View {
        HStack(spacing: DS.s2) {
            Image(systemName: isRecording ? "record.circle" : "keyboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isRecording ? DS.primary : DS.textSubtle)
                .frame(width: 24, height: 24)
                .background((isRecording ? DS.primary : DS.textSubtle).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))

            Text(LocalizedStringKey(title))
                .font(DS.body())
                .foregroundColor(DS.textStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Spacer(minLength: DS.s1)

            Text(value)
                .font(DS.caption())
                .foregroundColor(isRecording ? DS.primary : DS.textSecondary)
                .monospacedDigit()
                .lineLimit(1)

            Button {
                onRecord()
            } label: {
                Label(isRecording ? "Recording" : "Record Shortcut", systemImage: isRecording ? "record.circle.fill" : "record.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
            .tint(isRecording ? DS.primary : nil)
            .help(isRecording ? "Recording" : "Record Shortcut")
        }
        .padding(.horizontal, DS.s2)
        .padding(.vertical, DS.s2)
        .frame(minHeight: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            if isRecording {
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .stroke(DS.primary.opacity(0.26), lineWidth: 0.5)
            }
        }
    }

    private func statusRow(_ title: String, systemImage: String, tint: Color) -> some View {
        SWSettingsRow(title, systemImage: systemImage, tint: tint) {
            EmptyView()
        }
    }

    private func helperText(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(DS.caption())
            .foregroundColor(DS.textSubtle)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.s1)
    }

    @ViewBuilder
    private var aboutLogo: some View {
        if let image = MacAppIconController.image(for: settings.macTheme) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: DS.floatShadow.color, radius: DS.floatShadow.radius, x: DS.floatShadow.x, y: DS.floatShadow.y)
                .id(settings.macTheme)
        } else {
            Color.clear
                .frame(width: 82, height: 82)
        }
    }

    private func openStorageFolder() {
        guard let containerURL = vaultStore.storageContainerURL else {
            let alert = NSAlert()
            alert.messageText = L10n.string("Could Not Open Folder")
            alert.informativeText = L10n.string("No storage folder is currently available.")
            alert.addButton(withTitle: L10n.string("OK"))
            alert.runModal()
            return
        }

        if !NSWorkspace.shared.open(containerURL) {
            let alert = NSAlert()
            alert.messageText = L10n.string("Could Not Open Folder")
            alert.informativeText = L10n.string("Finder could not open: %@", containerURL.path)
            alert.addButton(withTitle: L10n.string("OK"))
            alert.runModal()
        }
    }

    private func openKeyLocation() {
        guard let displayPath = vaultStore.keyFileDisplayPath else {
            settingsErrorMessage = L10n.string("There is no key location to open.")
            return
        }

        let url = URL(fileURLWithPath: displayPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parentURL = url.deletingLastPathComponent()
            if !NSWorkspace.shared.open(parentURL) {
                settingsErrorMessage = L10n.string("Finder could not open: %@", parentURL.path)
            }
        }
    }

    private func openMaintenanceLogFolder() {
        let url = MaintenanceLogStore.shared.logsDirectory
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if !NSWorkspace.shared.open(url) {
                settingsErrorMessage = L10n.string("Finder could not open: %@", url.path)
            }
        } catch {
            settingsErrorMessage = L10n.string("Could not open the log folder: %@", error.localizedDescription)
        }
    }

    private func loadKey() {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Load Existing Key")
        panel.message = L10n.string("Seal Note reads the key file only on this Mac and never uploads it.")
        panel.allowedContentTypes = [.init(filenameExtension: "snkey")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                _ = try await vaultStore.importKeyFile(from: url)
            } catch {
                await MainActor.run {
                    handleKeyImportFailure(error, selectedURL: url)
                }
            }
        }
    }

    private func unloadKey() {
        if vaultStore.encryptedEntryCount == 0 {
            confirmRemoveKeyReference()
        } else if vaultStore.isKeyLoaded {
            confirmUsableKeyRemoval()
        } else {
            confirmInvalidKeyRemoval()
        }
    }

    private func confirmRemoveKeyReference() {
        let alert = NSAlert()
        alert.messageText = L10n.string("key.removeReference.confirmationTitle")
        alert.informativeText = L10n.string("Seal Note will forget the key location without deleting the key itself.")
        alert.addButton(withTitle: L10n.string("Remove Key Reference"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                try await vaultStore.unloadKey()
            } catch {
                await MainActor.run {
                    settingsErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func confirmUsableKeyRemoval() {
        let alert = NSAlert()
        alert.messageText = L10n.string("How Should Encrypted Notes Be Handled?")
        alert.informativeText = affectedEncryptedNotesMessage(prefix: L10n.string("Before removing the key reference, delete these encrypted notes or decrypt them all to plain text."))
        alert.addButton(withTitle: L10n.string("Delete All Encrypted Notes"))
        alert.addButton(withTitle: L10n.string("Decrypt All to Plain Text"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await runKeyRemovalAction { try await self.vaultStore.permanentlyDeleteAllEncryptedNotes() } }
        case .alertSecondButtonReturn:
            decryptAllEncryptedNotesAndRemoveKey()
        default:
            break
        }
    }

    private func confirmInvalidKeyRemoval() {
        let alert = NSAlert()
        alert.messageText = L10n.string("Remove the Invalid Key Reference?")
        alert.informativeText = affectedEncryptedNotesMessage(prefix: L10n.string("The current key is unavailable, so encrypted notes cannot be decrypted now. If you still have the original key, cancel and relocate it first."))
        alert.addButton(withTitle: L10n.string("Delete All Encrypted Notes"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await runKeyRemovalAction { try await self.vaultStore.permanentlyDeleteAllEncryptedNotes() } }
    }

    private func decryptAllEncryptedNotesAndRemoveKey() {
        Task { await runKeyRemovalAction { try await self.vaultStore.decryptAllEncryptedNotesAndRemoveKey() } }
    }

    private func runKeyRemovalAction(_ action: @escaping () async throws -> Int) async {
        do {
            _ = try await action()
            StickyNoteWindowManager.shared.closeAllWindows()
        } catch {
            await MainActor.run {
                settingsErrorMessage = error.localizedDescription
            }
        }
    }

    private func affectedEncryptedNotesMessage(prefix: String) -> String {
        L10n.string("%@\n\nThis affects %lld encrypted notes in the current list and Trash.", prefix, Int64(vaultStore.encryptedEntryCount))
    }

    private func createNewKey() {
        guard !vaultStore.hasKeyReference else {
            unloadKey()
            return
        }

        guard vaultStore.encryptedEntryCount == 0 else {
            confirmDeleteEncryptedNotesAndCreateKey()
            return
        }

        presentCreateKeyPanel()
    }

    private func confirmDeleteEncryptedNotesAndCreateKey() {
        let alert = NSAlert()
        alert.messageText = L10n.string("Creating a New Key Affects Existing Encrypted Notes")
        alert.informativeText = affectedEncryptedNotesMessage(prefix: L10n.string("A new key cannot unlock existing encrypted notes. These notes must be deleted before continuing."))
        alert.addButton(withTitle: L10n.string("Delete These Notes and Create a New Key"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                _ = try await vaultStore.permanentlyDeleteAllEncryptedNotes()
                await MainActor.run {
                    presentCreateKeyPanel()
                }
            } catch {
                await MainActor.run {
                    settingsErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func presentCreateKeyPanel() {
        let alert = NSAlert()
        alert.messageText = L10n.string("Create a New Key?")
        alert.informativeText = L10n.string("Save the key in a secure location. Losing it makes encrypted notes impossible to decrypt.")
        alert.addButton(withTitle: L10n.string("Create"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let savePanel = NSSavePanel()
        savePanel.title = L10n.string("Save Key")
        savePanel.message = L10n.string("After saving, Seal Note will remember this key location.")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        savePanel.nameFieldStringValue = "Seal Note-Key-\(formatter.string(from: Date())).snkey"
        savePanel.allowedContentTypes = [.init(filenameExtension: "snkey")!]
        guard savePanel.runModal() == .OK, let saveURL = savePanel.url else { return }

        Task {
            do {
                try await vaultStore.createKeyFile(at: saveURL)
            } catch {
                await MainActor.run {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = L10n.string("Creation Failed")
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.addButton(withTitle: L10n.string("OK"))
                    errorAlert.runModal()
                }
            }
        }
    }

    private func handleKeyImportFailure(_ error: Error, selectedURL: URL) {
        guard let keyError = error as? VaultKeyFileError, keyError == .keyMismatch else {
            settingsErrorMessage = error.localizedDescription
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.string("The Selected Key Cannot Unlock Existing Notes")
        alert.informativeText = affectedEncryptedNotesMessage(prefix: L10n.string("The selected key will not be saved by default."))
        alert.addButton(withTitle: L10n.string("Choose Another Key"))
        alert.addButton(withTitle: L10n.string("Delete These Notes and Use This Key"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        if alert.buttons.indices.contains(1) {
            alert.buttons[1].hasDestructiveAction = true
        }

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            loadKey()
        case .alertSecondButtonReturn:
            Task {
                do {
                    _ = try await vaultStore.permanentlyDeleteAllEncryptedNotes()
                    _ = try await vaultStore.importKeyFile(from: selectedURL)
                    StickyNoteWindowManager.shared.closeAllWindows()
                } catch {
                    await MainActor.run {
                        settingsErrorMessage = error.localizedDescription
                    }
                }
            }
        default:
            break
        }
    }
}

private extension View {
    func settingsFilledButton() -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(DS.primary)
    }

    func settingsDestructiveFilledButton() -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .tint(DS.destructive)
    }
}

#Preview("Settings - General") {
    MacSettingsView(selectedTab: .general)
}

#Preview("Settings - Editor") {
    MacSettingsView(selectedTab: .editor)
}

#Preview("Settings - Shortcuts") {
    MacSettingsView(selectedTab: .shortcuts)
}

#Preview("Settings - Key") {
    MacSettingsView(selectedTab: .key)
}

#Preview("Settings - About") {
    MacSettingsView(selectedTab: .about)
}

private enum MacShortcutRecordingAction: Equatable, Identifiable {
    case newNote
    case markdown(MarkdownShortcutAction)
    case editor(EditorShortcutAction)

    var id: String {
        switch self {
        case .newNote: return "newNote"
        case .markdown(let action): return "markdown.\(action.rawValue)"
        case .editor(let action): return "editor.\(action.rawValue)"
        }
    }
}

private struct MacSettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            content()
            Spacer(minLength: 0)
        }
        .padding(.top, DS.s6)
        .padding(.horizontal, DS.s3)
        .padding(.bottom, DS.s4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.bg)
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var recordingAction: MacShortcutRecordingAction?
    let onRecord: (MacShortcutRecordingAction, MarkdownShortcut) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = onRecord
        view.onCancel = { recordingAction = nil }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.recordingAction = recordingAction
        nsView.onRecord = onRecord
        nsView.onCancel = { recordingAction = nil }
        if recordingAction != nil {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class RecorderView: NSView {
        var recordingAction: MacShortcutRecordingAction?
        var onRecord: ((MacShortcutRecordingAction, MarkdownShortcut) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard let action = recordingAction else {
                super.keyDown(with: event)
                return
            }

            if event.keyCode == 53 {
                onCancel?()
                return
            }

            guard let keyEquivalent = event.charactersIgnoringModifiers?.lowercased(), !keyEquivalent.isEmpty else {
                return
            }

            let shortcut = MarkdownShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: ShortcutStore.carbonModifiers(from: event.modifierFlags),
                keyEquivalent: keyEquivalent
            )
            onRecord?(action, shortcut)
        }
    }
}
