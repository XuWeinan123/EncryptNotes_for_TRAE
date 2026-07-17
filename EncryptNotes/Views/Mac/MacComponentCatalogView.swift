#if os(macOS)
import AppKit
import SwiftUI

struct MacComponentCatalogView: View {
    fileprivate enum ComponentKind {
        case system
        case custom

        var title: String {
            switch self {
            case .system: return "System Components"
            case .custom: return "Custom Components"
            }
        }

        var badgeStyle: SWStatusBadgeStyle {
            switch self {
            case .system: return .neutral
            case .custom: return .success
            }
        }
    }

    fileprivate struct ComponentEntry: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        let source: String
        let kind: ComponentKind
    }

    @State private var previewController = MacComponentPreviewWindowController()

    private static let systemComponents: [ComponentEntry] = [
        ComponentEntry(name: "Alert / Sheet / ConfirmationDialog", description: "Error, confirmation, editing, and export flows.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Button", description: "Basic actions, toolbar actions, and form actions.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Image / SF Symbols", description: "Icons, status indicators, and button graphics.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "LazyVStack / LazyVGrid", description: "Lists, two-column shortcut layouts, and grid content.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "List", description: "All Notes, Trash, and Settings collections.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Menu", description: "More actions, menu bar lists, and note context actions.", source: "SwiftUI / AppKit NSMenu", kind: .system),
        ComponentEntry(name: "NSHostingView", description: "Hosts SwiftUI content in a macOS window.", source: "AppKit", kind: .system),
        ComponentEntry(name: "NSStatusItem", description: "A macOS menu bar entry point.", source: "AppKit", kind: .system),
        ComponentEntry(name: "NSTextView / NSScrollView", description: "The macOS note editor and Markdown highlighting experience.", source: "AppKit", kind: .system),
        ComponentEntry(name: "NSWindow", description: "Note, All Notes, Trash, Settings, and component catalog windows.", source: "AppKit", kind: .system),
        ComponentEntry(name: "Picker", description: "Segmented options and mode selection for settings.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "ProgressView", description: "Waiting states for import, export, and loading.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "ScrollView", description: "Scroll containers for Settings, About, and the component catalog.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "SecureField", description: "Input for keys and sensitive fields.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Slider", description: "Editor font size, line height, and opacity settings.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "TabView", description: "Settings page columns.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "TextField", description: "Search, title, path, and API key input.", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Toggle", description: "Toggle rows for settings.", source: "SwiftUI", kind: .system)
    ]

    private static let customComponents: [ComponentEntry] = [
        ComponentEntry(name: "SWStatusBadge", description: "Status badges.", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWSectionPanel", description: "Grouped panels for settings and information pages.", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWSettingsRow", description: "Settings list rows.", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWRowDivider", description: "Settings row dividers.", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWEmptyState", description: "Empty-state presentation.", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWFilterChip", description: "Tag and filter chips.", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "AllNotesListRow", description: "Custom list rows for the All Notes window.", source: "Views/Mac/AllNotesWindow.swift", kind: .custom),
        ComponentEntry(name: "MacListSearchBar", description: "Search bars for macOS list windows.", source: "Views/Mac/AllNotesWindow.swift", kind: .custom),
        ComponentEntry(name: "TrashListRow", description: "Custom list rows for the Trash window.", source: "Views/Mac/TrashWindow.swift", kind: .custom),
        ComponentEntry(name: "MacMarkdownPreview", description: "A macOS Markdown preview view.", source: "Views/Mac/StickyNoteEditorView.swift", kind: .custom)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.s4) {
                header
                componentSection(title: ComponentKind.system.title, entries: Self.systemComponents)
                componentSection(title: ComponentKind.custom.title, entries: Self.customComponents)
            }
            .padding(.horizontal, DS.s6)
            .padding(.top, DS.s6)
            .padding(.bottom, DS.s8)
        }
        .frame(minWidth: 680, minHeight: 560)
        .background(DS.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            Text("View Components")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DS.textEmphasize)

            HStack(spacing: DS.s2) {
                SWStatusBadge(L10n.string("System Components %lld", Int64(Self.systemComponents.count)), systemImage: "macwindow", style: .neutral)
                SWStatusBadge(L10n.string("Custom Components %lld", Int64(Self.customComponents.count)), systemImage: "shippingbox", style: .success)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func componentSection(title: String, entries: [ComponentEntry]) -> some View {
        let sortedEntries = entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return VStack(alignment: .leading, spacing: DS.s3) {
            Text(LocalizedStringKey(title))
                .font(DS.title())
                .foregroundStyle(DS.textStrong)

            VStack(spacing: 0) {
                ForEach(Array(sortedEntries.enumerated()), id: \.element.id) { index, entry in
                    componentRow(entry)

                    if index < sortedEntries.count - 1 {
                        Divider()
                            .padding(.leading, DS.s4)
                    }
                }
            }
            .background(DS.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .stroke(DS.line, lineWidth: 0.5)
            )
        }
    }

    private func componentRow(_ entry: ComponentEntry) -> some View {
        Button {
            previewController.open(entry)
        } label: {
            HStack(alignment: .center, spacing: DS.s3) {
                VStack(alignment: .leading, spacing: DS.s1) {
                    HStack(spacing: DS.s2) {
                        Text(LocalizedStringKey(entry.name))
                            .font(DS.bodyLg().weight(.semibold))
                            .foregroundStyle(DS.textEmphasize)
                            .lineLimit(1)

                        SWStatusBadge(entry.kind.title, style: entry.kind.badgeStyle)
                    }

                    Text(LocalizedStringKey(entry.description))
                        .font(DS.caption())
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: DS.s4)

                HStack(spacing: DS.s2) {
                    Text(entry.source)
                        .font(DS.mono())
                        .foregroundStyle(DS.textSubtle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 240, alignment: .trailing)

                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.textSubtle)
                }
            }
            .padding(.horizontal, DS.s4)
            .padding(.vertical, DS.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy Name", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.name, forType: .string)
            }
        }
        .help(L10n.string("View %@", entry.name))
    }
}

@MainActor
private final class MacComponentPreviewWindowController: NSObject, NSWindowDelegate {
    private var windows: [UUID: NSWindow] = [:]

    func open(_ entry: MacComponentCatalogView.ComponentEntry) {
        if let window = windows[entry.id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 900),
            styleMask: [.titled, .closable, .resizable, .unifiedTitleAndToolbar, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = entry.name
        window.contentView = NSHostingView(rootView: MacComponentPreviewView(entry: entry))
        window.contentMinSize = NSSize(width: 560, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        windows[entry.id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === closingWindow })?.key else { return }
        windows[id] = nil
    }
}

private struct MacComponentPreviewView: View {
    let entry: MacComponentCatalogView.ComponentEntry

    @State private var toggleValue = true
    @State private var sliderValue = 0.64
    @State private var textValue = "Seal Note"
    @State private var secureValue = "seal-note-key"
    @State private var draft = "Capture a quick #idea"
    @State private var pickerValue = "Plain Text"
    @State private var markdownScrollY: CGFloat = 0
    @State private var isToolbarHovered = false
    @State private var isAlertPresented = false
    @State private var isSheetPresented = false
    @State private var isConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s4) {
            header

            VStack(alignment: .leading, spacing: DS.s3) {
                Text("Preview")
                    .font(DS.title())
                    .foregroundStyle(DS.textStrong)

                previewContent
                    .frame(maxWidth: .infinity, minHeight: 540, alignment: .center)
                    .padding(DS.s4)
                    .background(DS.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                            .stroke(DS.line, lineWidth: 0.5)
                    )
            }

            Spacer(minLength: 0)
        }
        .padding(DS.s6)
        .frame(minWidth: 560, minHeight: 520)
        .background(DS.bg)
        .alert("System Alert", isPresented: $isAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This is a real SwiftUI alert.")
        }
        .sheet(isPresented: $isSheetPresented) {
            VStack(spacing: DS.s3) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(DS.primary)
                Text("System Sheet")
                    .font(DS.title())
                Button("Close") { isSheetPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(DS.s6)
            .frame(width: 320, height: 220)
        }
        .confirmationDialog("Confirm Action", isPresented: $isConfirmationPresented) {
            Button("Continue") {}
            Button("Delete", role: .destructive) {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is a real confirmation dialog.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            HStack(spacing: DS.s2) {
                Text(LocalizedStringKey(entry.name))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(DS.textEmphasize)
                    .lineLimit(1)

                SWStatusBadge(entry.kind.title, style: entry.kind.badgeStyle)
            }

            Text(LocalizedStringKey(entry.description))
                .font(DS.body())
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)

            Text(entry.source)
                .font(DS.mono())
                .foregroundStyle(DS.textSubtle)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch entry.name {
        case "Button":
            VStack(alignment: .leading, spacing: DS.s4) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: DS.s4
                ) {
                    buttonStylePreview("Automatic") {
                        Button("System Button") {}
                            .buttonStyle(.automatic)
                    }
                    buttonStylePreview("Borderless") {
                        Button("System Button") {}
                            .buttonStyle(.borderless)
                    }
                    buttonStylePreview("Bordered") {
                        Button("System Button") {}
                            .buttonStyle(.bordered)
                    }
                    buttonStylePreview("Bordered Prominent") {
                        Button("System Button") {}
                            .buttonStyle(.borderedProminent)
                            .tint(DS.primary)
                    }
                    buttonStylePreview("Glass") {
                        Button("System Button") {}
                            .buttonStyle(.glass)
                    }
                    buttonStylePreview("Glass Prominent") {
                        Button("System Button") {}
                            .buttonStyle(.glassProminent)
                            .tint(DS.primary)
                    }
                    buttonStylePreview("Link") {
                        Button("System Button") {}
                            .buttonStyle(.link)
                    }
                    buttonStylePreview("Plain") {
                        Button("System Button") {}
                            .buttonStyle(.plain)
                    }
                }
                .controlSize(.large)

                Divider()

                Text("Bordered Prominent · Control Size")
                    .font(DS.title())
                    .foregroundStyle(DS.textStrong)

                HStack(alignment: .bottom, spacing: DS.s3) {
                    controlSizePreview("Mini", size: .mini)
                    controlSizePreview("Small", size: .small)
                    controlSizePreview("Regular", size: .regular)
                    controlSizePreview("Large", size: .large)
                    controlSizePreview("Extra Large", size: .extraLarge)
                }
            }
            .frame(width: 560)
        case "Menu":
            Menu {
                Button("Open") {}
                Button("Rename") {}
                Divider()
                Button("Delete", role: .destructive) {}
            } label: {
                Label("More Actions", systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
        case "Picker":
            Picker("Save Mode", selection: $pickerValue) {
                Text("Plain Text").tag("Plain Text")
                Text("Encrypted").tag("Encrypted")
            }
            .pickerStyle(.segmented)
            .tint(DS.primary)
            .frame(width: 220)
        case "Toggle":
            Toggle("Enable Logging", isOn: $toggleValue)
                .toggleStyle(.switch)
                .frame(width: 220)
        case "Slider":
            VStack(alignment: .leading, spacing: DS.s2) {
                Text(L10n.string("Opacity %lld%%", Int64(sliderValue * 100)))
                    .font(DS.caption())
                    .foregroundStyle(DS.textSecondary)
                Slider(value: $sliderValue)
            }
            .frame(width: 260)
        case "TextField":
            TextField("Search Notes…", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        case "SecureField":
            SecureField("Enter Key", text: $secureValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        case "TextEditor":
            TextEditor(text: $draft)
                .font(DS.body())
                .frame(width: 300, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
        case "List":
            List {
                Text("Seal Note Iteration Log")
                Text("Connector UI Questions")
                Text("Feature Test")
            }
            .frame(width: 320, height: 150)
        case "ScrollView":
            ScrollView {
                VStack(alignment: .leading, spacing: DS.s2) {
                    ForEach(1...8, id: \.self) { index in
                        Text(L10n.string("Scrollable Content %lld", Int64(index)))
                            .font(DS.body())
                    }
                }
            }
            .frame(width: 240, height: 130)
        case "LazyVStack / LazyVGrid":
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.s2) {
                ForEach(1...4, id: \.self) { index in
                    Text("Item \(index)")
                        .font(DS.caption())
                        .frame(maxWidth: .infinity)
                        .padding(DS.s3)
                        .background(DS.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
                }
            }
            .frame(width: 280)
        case "TabView":
            TabView {
                Text("General").tabItem { Label("General", systemImage: "gear") }
                Text("About").tabItem { Label("About", systemImage: "info.circle") }
            }
            .frame(width: 320, height: 180)
        case "ProgressView":
            VStack(spacing: DS.s3) {
                ProgressView()
                ProgressView(value: sliderValue)
                    .frame(width: 220)
            }
        case "Image / SF Symbols":
            HStack(spacing: DS.s4) {
                Image(systemName: "note.text")
                Image(systemName: "lock.fill")
                Image(systemName: "magnifyingglass")
            }
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(DS.primary)
        case "Alert / Sheet / ConfirmationDialog":
            HStack(spacing: DS.s3) {
                Button("Show Alert") { isAlertPresented = true }
                Button("Show Update Alert") {
                    GitHubReleaseUpdateChecker.shared.presentUpdateAlertPreview()
                }
                Button("Show Sheet") { isSheetPresented = true }
                Button("Show Confirmation Dialog") { isConfirmationPresented = true }
            }
            .buttonStyle(.bordered)
        case "NSWindow":
            VStack(spacing: DS.s3) {
                Image(systemName: "macwindow")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(DS.primary)
                Text("The current detail window is an NSWindow")
                    .font(DS.title())
                Text("titled · closable · resizable · unifiedTitleAndToolbar")
                    .font(DS.mono())
                    .foregroundStyle(DS.textSecondary)
            }
        case "NSStatusItem":
            AppKitStatusItemButtonPreview()
                .frame(width: 180, height: 44)
        case "NSHostingView":
            AppKitHostingViewPreview()
                .frame(width: 360, height: 160)
        case "NSTextView / NSScrollView":
            MacTextView(
                text: $draft,
                placeholder: "Enter Markdown",
                fontSize: 16,
                lineHeightMultiple: 1.35,
                autoFocus: false,
                onChange: { draft = $0 },
                onSaveShortcut: {},
                onApplyShortcut: {},
                onFitToContent: {},
                onCopyShortcut: {},
                onFindShortcut: {},
                onToggleMarkdownPreview: {},
                onIncreaseFontSize: {},
                onDecreaseFontSize: {},
                onFindVisibilityChange: { _ in }
            )
            .frame(width: 520, height: 300)
        case "NavigationStack":
            NavigationStack {
                List {
                    NavigationLink("Open Note Details") {
                        Text("NavigationStack Detail")
                            .font(DS.title())
                    }
                }
                .navigationTitle("Notes")
            }
            .frame(width: 420, height: 360)
        case "SWShimmer":
            SWShimmer {
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .fill(DS.surfaceSunken)
                    .frame(width: 260, height: 84)
            }
        case "SWStatusBadge":
            HStack(spacing: DS.s2) {
                SWStatusBadge("System Components", style: .neutral)
                SWStatusBadge("Enabled", systemImage: "checkmark", style: .success)
                SWStatusBadge("30 Days", systemImage: "clock", style: .warning)
            }
        case "SWSectionPanel":
            SWSectionPanel("Section Title", footer: "Footer text appears here.") {
                SWSettingsRow("Setting", subtitle: "Description", systemImage: "gear") {
                    EmptyView()
                }
            }
            .frame(width: 340)
        case "SWPanelStack":
            SWPanelStack {
                SWSectionPanel("First Section") { Text("Content Area").font(DS.body()) }
                SWSectionPanel("Second Section") { Text("Content Area").font(DS.body()) }
            }
            .frame(width: 340)
        case "SWPageHeader":
            SWPageHeader(title: "Page Title", subtitle: "Page Description", systemImage: "sparkles")
                .frame(width: 340)
        case "SWSettingsRow":
            SWSettingsRow("Setting", subtitle: "Buttons or status can appear on the right", systemImage: "slider.horizontal.3") {
                SWStatusBadge("Saved", style: .success)
            }
            .frame(width: 360)
        case "SWRowDivider":
            VStack(spacing: 0) {
                SWSettingsRow("Previous Row", systemImage: "1.circle") { EmptyView() }
                SWRowDivider()
                SWSettingsRow("Next Row", systemImage: "2.circle") { EmptyView() }
            }
            .frame(width: 360)
        case "SWEmptyState":
            SWEmptyState(title: "No Content", message: "Content will appear here.", systemImage: "tray")
        case "SWFilterChip":
            HStack(spacing: DS.s2) {
                SWFilterChip(title: "All", isSelected: true) {}
                SWFilterChip(title: "Work", isSelected: false) {}
            }
        case "NoteCardView":
            NoteCardView(
                note: Note(
                    id: "component-preview-note",
                    body: "# Seal Note Iteration Log\n\nComponent details now show a real note card. #components",
                    createdAt: Date().addingTimeInterval(-3_600),
                    updatedAt: Date().addingTimeInterval(-120)
                ),
                onTap: {},
                onEdit: {},
                onDelete: {}
            )
            .frame(width: 420)
        case "EncryptedCardView":
            EncryptedCardView(
                info: EncryptedNoteInfo(
                    id: "component-preview-encrypted-note",
                    url: URL(fileURLWithPath: "/tmp/component-preview.md"),
                    title: "Encrypted Note Example",
                    ciphertextPreview: "snenc:v1:eyJub25jZSI6Ik...",
                    fileSize: 2_048,
                    createdAt: Date().addingTimeInterval(-7_200),
                    updatedAt: Date().addingTimeInterval(-300)
                ),
                isKeyLoaded: false,
                onOpen: {},
                onDelete: {}
            )
            .frame(width: 420)
        case "AllNotesView":
            AllNotesView()
                .frame(width: 660, height: 560)
        case "AllNotesListRow":
            AllNotesListRow(
                title: "Seal Note Iteration Log",
                subtitle: "Component details show a real All Notes list row",
                isLocked: false,
                timeText: "Just now",
                onOpen: {}
            ) {
                Button("Rename") {}
                Button("Delete", role: .destructive) {}
            }
            .frame(width: 520)
        case "MacListSearchBar":
            MacListSearchBar(placeholder: "Search Notes…", text: $textValue, onClose: {})
                .frame(width: 380)
        case "MacListSearchToolbarAppearance":
            VStack(spacing: DS.s3) {
                MacListSearchBar(placeholder: "Search Notes…", text: $textValue, onClose: {})
                    .frame(width: 460)
                Text("This bridge switches the current detail window to a search toolbar appearance")
                    .font(DS.caption())
                    .foregroundStyle(DS.textSecondary)
            }
            .background(MacListSearchToolbarAppearance(isActive: true))
        case "TrashView":
            TrashView()
                .frame(width: 660, height: 560)
        case "TrashListRow":
            TrashListRow(
                title: "Deleted Encrypted Note",
                subtitle: "Deleted yesterday · permanently deleted in 29 days"
            ) {
                HStack(spacing: DS.s2) {
                    SWStatusBadge("Encrypted", systemImage: "lock.fill", style: .neutral)
                    SWStatusBadge("29 Days", systemImage: "clock", style: .warning)
                }
            }
            .frame(width: 520)
        case "MacSettingsView":
            MacSettingsView(selectedTab: .general)
        case "MacComponentCatalogView":
            MacComponentCatalogView()
                .frame(width: 680, height: 560)
        case "MacIntroView":
            MacIntroView()
                .scaleEffect(0.78)
                .frame(width: 520, height: 580)
        case "StickyNoteEditorView":
            StickyNoteEditorView(
                note: Note(
                    id: "component-preview-editor",
                    body: "# Markdown Editor\n\nThis is a real preview of the floating note editor.",
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                isPreview: true
            )
            .frame(width: 520, height: 440)
        case "MacTextView":
            MacTextView(
                text: $draft,
                placeholder: "Write something…",
                fontSize: 16,
                lineHeightMultiple: 1.35,
                autoFocus: false,
                onChange: { draft = $0 },
                onSaveShortcut: {},
                onApplyShortcut: {},
                onFitToContent: {},
                onCopyShortcut: {},
                onFindShortcut: {},
                onToggleMarkdownPreview: {},
                onIncreaseFontSize: {},
                onDecreaseFontSize: {},
                onFindVisibilityChange: { _ in }
            )
            .frame(width: 520, height: 360)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
        case "MacMarkdownPreview":
            MacMarkdownPreview(
                text: "# Markdown Preview\n\n- **Bold** and *italic*\n- `inline code`\n\n> This is the actual Markdown rendering component.",
                fontSize: 16,
                lineHeightMultiple: 1.35,
                scrollY: $markdownScrollY
            )
            .frame(width: 520, height: 360)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))
        case "MacToolbarHoverRegion":
            ZStack {
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .fill(isToolbarHovered ? DS.primaryContainer : DS.surfaceSunken)
                VStack(spacing: DS.s2) {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.system(size: 28, weight: .semibold))
                    Text(isToolbarHovered ? "Pointer is inside the toolbar region" : "Move the pointer into this region")
                        .font(DS.body())
                }
                .foregroundStyle(isToolbarHovered ? DS.primaryDeep : DS.textSecondary)
                MacToolbarHoverRegion { isToolbarHovered = $0 }
            }
            .frame(width: 520, height: 120)
        default:
            placeholderPreview(systemImage: iconName(for: entry.name), title: entry.name, subtitle: entry.description)
        }
    }

    private func placeholderPreview(systemImage: String, title: String, subtitle: String) -> some View {
        VStack(spacing: DS.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(DS.primary)
                .frame(width: 64, height: 64)
                .background(DS.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: DS.rMd, style: .continuous))

            Text(LocalizedStringKey(title))
                .font(DS.title())
                .foregroundStyle(DS.textStrong)

            Text(LocalizedStringKey(subtitle))
                .font(DS.caption())
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: 320)
    }

    private func buttonStylePreview<Content: View>(
        _ name: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text(name)
                .font(DS.mono())
                .foregroundStyle(DS.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }

    private func controlSizePreview(_ name: String, size: ControlSize) -> some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text(name)
                .font(DS.mono())
                .foregroundStyle(DS.textSecondary)
            Button("System Button") {}
                .buttonStyle(.borderedProminent)
                .controlSize(size)
                .tint(DS.primary)
        }
    }

    private func iconName(for name: String) -> String {
        if name.localizedCaseInsensitiveContains("trash") { return "trash" }
        if name.localizedCaseInsensitiveContains("note") { return "note.text" }
        if name.localizedCaseInsensitiveContains("lock") || name.localizedCaseInsensitiveContains("encrypted") { return "lock.fill" }
        if name.localizedCaseInsensitiveContains("settings") { return "gear" }
        if name.localizedCaseInsensitiveContains("markdown") || name.localizedCaseInsensitiveContains("text") { return "text.alignleft" }
        if name.localizedCaseInsensitiveContains("window") || name.localizedCaseInsensitiveContains("view") { return "macwindow" }
        return "square.grid.2x2"
    }
}

private struct AppKitHostingViewPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> NSHostingView<AnyView> {
        NSHostingView(rootView: AnyView(
            VStack(spacing: DS.s2) {
                Image(systemName: "swift")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(DS.primary)
                Text("SwiftUI content hosted by NSHostingView")
                    .font(DS.body())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.surfaceSunken)
        ))
    }

    func updateNSView(_ nsView: NSHostingView<AnyView>, context: Context) {}
}

private struct AppKitStatusItemButtonPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> NSStatusBarButton {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 180, height: 44))
        button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Seal Note")
        button.title = " Seal Note"
        button.imagePosition = .imageLeading
        button.bezelStyle = .regularSquare
        return button
    }

    func updateNSView(_ nsView: NSStatusBarButton, context: Context) {}
}
#endif
