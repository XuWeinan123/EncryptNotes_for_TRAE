#if os(macOS)
import AppKit
import SwiftUI

struct MacComponentCatalogView: View {
    fileprivate enum ComponentKind {
        case system
        case custom

        var title: String {
            switch self {
            case .system: return "系统组件"
            case .custom: return "自建组件"
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
        ComponentEntry(name: "Alert / Sheet / ConfirmationDialog", description: "错误、确认、编辑和导出流程。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Button", description: "基础点击动作、工具栏动作和表单尾部操作。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Image / SF Symbols", description: "图标、状态标识和按钮图形。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "LazyVStack / LazyVGrid", description: "列表、快捷键双列布局和栅格内容。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "List", description: "全部笔记、回收站和设置集合。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Menu", description: "更多操作、菜单栏列表和笔记上下文操作。", source: "SwiftUI / AppKit NSMenu", kind: .system),
        ComponentEntry(name: "NSHostingView", description: "把 SwiftUI 内容承载到 macOS 窗口。", source: "AppKit", kind: .system),
        ComponentEntry(name: "NSStatusItem", description: "macOS 菜单栏入口。", source: "AppKit", kind: .system),
        ComponentEntry(name: "NSTextView / NSScrollView", description: "macOS 便签编辑器和 Markdown 高亮编辑体验。", source: "AppKit", kind: .system),
        ComponentEntry(name: "NSWindow", description: "便签、全部笔记、回收站、设置和组件目录窗口。", source: "AppKit", kind: .system),
        ComponentEntry(name: "NavigationStack", description: "iOS 页面导航。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Picker", description: "设置页分段选项和模式选择。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "ProgressView", description: "导入、导出、加载等等待状态。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "ScrollView", description: "设置页、关于页和组件目录滚动容器。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "SecureField", description: "密钥与敏感字段输入。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Slider", description: "编辑器字号、行高和透明度设置。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "TabView", description: "设置页分栏。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "TextEditor", description: "iOS 笔记正文编辑。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "TextField", description: "搜索、标题、路径和 API Key 输入。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Toggle", description: "设置页开关项。", source: "SwiftUI", kind: .system)
    ]

    private static let customComponents: [ComponentEntry] = [
        ComponentEntry(name: "SWShimmer", description: "加载占位的扫光效果。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWStatusBadge", description: "状态胶囊标签。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWSectionPanel", description: "设置页和信息页的分组面板。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWPanelStack", description: "设置内容的统一竖向容器。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWPageHeader", description: "页面标题区域。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWSettingsRow", description: "设置页列表行。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWRowDivider", description: "设置列表行分割线。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWEmptyState", description: "空状态展示。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWFilterChip", description: "标签和过滤条件胶囊。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "NoteCardView", description: "明文笔记卡片。", source: "Views/Components/NoteCardView.swift", kind: .custom),
        ComponentEntry(name: "EncryptedCardView", description: "加密笔记卡片。", source: "Views/Components/EncryptedCardView.swift", kind: .custom),
        ComponentEntry(name: "AllNotesView", description: "macOS 全部笔记窗口。", source: "Views/Mac/AllNotesWindow.swift", kind: .custom),
        ComponentEntry(name: "AllNotesListRow", description: "全部笔记窗口的自定义列表项。", source: "Views/Mac/AllNotesWindow.swift", kind: .custom),
        ComponentEntry(name: "AllNotesRenameSheet", description: "全部笔记中的重命名弹窗。", source: "Views/Mac/AllNotesWindow.swift", kind: .custom),
        ComponentEntry(name: "MacListSearchBar", description: "macOS 列表窗口搜索栏。", source: "Views/Mac/AllNotesWindow.swift", kind: .custom),
        ComponentEntry(name: "MacListSearchToolbarAppearance", description: "macOS 搜索工具栏外观桥接。", source: "Views/Mac/AllNotesWindow.swift", kind: .custom),
        ComponentEntry(name: "TrashView", description: "macOS 回收站窗口。", source: "Views/Mac/TrashWindow.swift", kind: .custom),
        ComponentEntry(name: "TrashListRow", description: "回收站窗口的自定义列表项。", source: "Views/Mac/TrashWindow.swift", kind: .custom),
        ComponentEntry(name: "MacSettingsView", description: "macOS 设置窗口。", source: "Views/Mac/MacSettingsView.swift", kind: .custom),
        ComponentEntry(name: "MacComponentCatalogView", description: "当前组件目录窗口。", source: "Views/Mac/MacComponentCatalogView.swift", kind: .custom),
        ComponentEntry(name: "MacIntroView", description: "macOS 首次启动介绍页。", source: "Views/Mac/MacIntroView.swift", kind: .custom),
        ComponentEntry(name: "StickyNoteEditorView", description: "macOS 悬浮便签编辑器。", source: "Views/Mac/StickyNoteEditorView.swift", kind: .custom),
        ComponentEntry(name: "MacTextView", description: "AppKit 桥接的 macOS Markdown 编辑器。", source: "Views/Mac/StickyNoteEditorView.swift", kind: .custom),
        ComponentEntry(name: "MacMarkdownPreview", description: "macOS Markdown 预览视图。", source: "Views/Mac/StickyNoteEditorView.swift", kind: .custom),
        ComponentEntry(name: "MacToolbarHoverRegion", description: "悬浮便签工具栏 hover 区域。", source: "Views/Mac/StickyNoteEditorView.swift", kind: .custom)
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
            Text("查看组件")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DS.textEmphasize)

            HStack(spacing: DS.s2) {
                SWStatusBadge("系统组件 \(Self.systemComponents.count)", systemImage: "macwindow", style: .neutral)
                SWStatusBadge("自建组件 \(Self.customComponents.count)", systemImage: "shippingbox", style: .success)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func componentSection(title: String, entries: [ComponentEntry]) -> some View {
        let sortedEntries = entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return VStack(alignment: .leading, spacing: DS.s3) {
            Text(title)
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
                        Text(entry.name)
                            .font(DS.bodyLg().weight(.semibold))
                            .foregroundStyle(DS.textEmphasize)
                            .lineLimit(1)

                        SWStatusBadge(entry.kind.title, style: entry.kind.badgeStyle)
                    }

                    Text(entry.description)
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
        .help("查看 \(entry.name)")
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
    @State private var draft = "快速记录一条 #想法"
    @State private var pickerValue = "明文"
    @State private var renameTitle = "Seal Note 迭代记录"
    @State private var markdownScrollY: CGFloat = 0
    @State private var isToolbarHovered = false
    @State private var isAlertPresented = false
    @State private var isSheetPresented = false
    @State private var isConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s4) {
            header

            VStack(alignment: .leading, spacing: DS.s3) {
                Text("预览")
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
        .alert("系统 Alert", isPresented: $isAlertPresented) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("这是 SwiftUI Alert 的真实展示。")
        }
        .sheet(isPresented: $isSheetPresented) {
            VStack(spacing: DS.s3) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(DS.primary)
                Text("系统 Sheet")
                    .font(DS.title())
                Button("关闭") { isSheetPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(DS.s6)
            .frame(width: 320, height: 220)
        }
        .confirmationDialog("确认操作", isPresented: $isConfirmationPresented) {
            Button("继续") {}
            Button("删除", role: .destructive) {}
            Button("取消", role: .cancel) {}
        } message: {
            Text("这是 ConfirmationDialog 的真实展示。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            HStack(spacing: DS.s2) {
                Text(entry.name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(DS.textEmphasize)
                    .lineLimit(1)

                SWStatusBadge(entry.kind.title, style: entry.kind.badgeStyle)
            }

            Text(entry.description)
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
                        Button("系统按钮") {}
                            .buttonStyle(.automatic)
                    }
                    buttonStylePreview("Borderless") {
                        Button("系统按钮") {}
                            .buttonStyle(.borderless)
                    }
                    buttonStylePreview("Bordered") {
                        Button("系统按钮") {}
                            .buttonStyle(.bordered)
                    }
                    buttonStylePreview("Bordered Prominent") {
                        Button("系统按钮") {}
                            .buttonStyle(.borderedProminent)
                            .tint(DS.primary)
                    }
                    buttonStylePreview("Glass") {
                        Button("系统按钮") {}
                            .buttonStyle(.glass)
                    }
                    buttonStylePreview("Glass Prominent") {
                        Button("系统按钮") {}
                            .buttonStyle(.glassProminent)
                            .tint(DS.primary)
                    }
                    buttonStylePreview("Link") {
                        Button("系统按钮") {}
                            .buttonStyle(.link)
                    }
                    buttonStylePreview("Plain") {
                        Button("系统按钮") {}
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
                Button("打开") {}
                Button("重命名") {}
                Divider()
                Button("删除", role: .destructive) {}
            } label: {
                Label("更多操作", systemImage: "ellipsis.circle")
            }
            .menuStyle(.button)
        case "Picker":
            Picker("保存方式", selection: $pickerValue) {
                Text("明文").tag("明文")
                Text("加密").tag("加密")
            }
            .pickerStyle(.segmented)
            .tint(DS.primary)
            .frame(width: 220)
        case "Toggle":
            Toggle("开启日志记录", isOn: $toggleValue)
                .toggleStyle(.switch)
                .frame(width: 220)
        case "Slider":
            VStack(alignment: .leading, spacing: DS.s2) {
                Text("透明度 \(Int(sliderValue * 100))%")
                    .font(DS.caption())
                    .foregroundStyle(DS.textSecondary)
                Slider(value: $sliderValue)
            }
            .frame(width: 260)
        case "TextField":
            TextField("搜索笔记...", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        case "SecureField":
            SecureField("输入密钥", text: $secureValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        case "TextEditor":
            TextEditor(text: $draft)
                .font(DS.body())
                .frame(width: 300, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: DS.rSm, style: .continuous))
        case "List":
            List {
                Text("Seal Note 迭代记录")
                Text("连接器界面疑问")
                Text("功能测试")
            }
            .frame(width: 320, height: 150)
        case "ScrollView":
            ScrollView {
                VStack(alignment: .leading, spacing: DS.s2) {
                    ForEach(1...8, id: \.self) { index in
                        Text("滚动内容 \(index)")
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
                Text("通用").tabItem { Label("通用", systemImage: "gear") }
                Text("关于").tabItem { Label("关于", systemImage: "info.circle") }
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
                Button("显示 Alert") { isAlertPresented = true }
                Button("显示 Sheet") { isSheetPresented = true }
                Button("显示确认菜单") { isConfirmationPresented = true }
            }
            .buttonStyle(.bordered)
        case "NSWindow":
            VStack(spacing: DS.s3) {
                Image(systemName: "macwindow")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(DS.primary)
                Text("当前详情窗口就是一个 NSWindow")
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
                placeholder: "输入 Markdown",
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
                    NavigationLink("打开笔记详情") {
                        Text("NavigationStack 详情页")
                            .font(DS.title())
                    }
                }
                .navigationTitle("笔记")
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
                SWStatusBadge("系统组件", style: .neutral)
                SWStatusBadge("已启用", systemImage: "checkmark", style: .success)
                SWStatusBadge("剩 30 天", systemImage: "clock", style: .warning)
            }
        case "SWSectionPanel":
            SWSectionPanel("分组标题", footer: "这里是 footer 文案。") {
                SWSettingsRow("设置项", subtitle: "说明文本", systemImage: "gear") {
                    EmptyView()
                }
            }
            .frame(width: 340)
        case "SWPanelStack":
            SWPanelStack {
                SWSectionPanel("第一组") { Text("内容区域").font(DS.body()) }
                SWSectionPanel("第二组") { Text("内容区域").font(DS.body()) }
            }
            .frame(width: 340)
        case "SWPageHeader":
            SWPageHeader(title: "页面标题", subtitle: "页面说明", systemImage: "sparkles")
                .frame(width: 340)
        case "SWSettingsRow":
            SWSettingsRow("设置项", subtitle: "右侧可放按钮或状态", systemImage: "slider.horizontal.3") {
                SWStatusBadge("已保存", style: .success)
            }
            .frame(width: 360)
        case "SWRowDivider":
            VStack(spacing: 0) {
                SWSettingsRow("上一行", systemImage: "1.circle") { EmptyView() }
                SWRowDivider()
                SWSettingsRow("下一行", systemImage: "2.circle") { EmptyView() }
            }
            .frame(width: 360)
        case "SWEmptyState":
            SWEmptyState(title: "暂无内容", message: "内容会在这里显示。", systemImage: "tray")
        case "SWFilterChip":
            HStack(spacing: DS.s2) {
                SWFilterChip(title: "全部", isSelected: true) {}
                SWFilterChip(title: "工作", isSelected: false) {}
            }
        case "NoteCardView":
            NoteCardView(
                note: Note(
                    id: "component-preview-note",
                    body: "# Seal Note 迭代记录\n\n组件详情现在会展示真实的笔记卡片。 #组件",
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
                    title: "加密笔记示例",
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
                title: "Seal Note 迭代记录",
                subtitle: "组件详情展示真实的全部笔记列表项",
                isLocked: false,
                timeText: "刚刚",
                onOpen: {}
            ) {
                Button("重命名") {}
                Button("删除", role: .destructive) {}
            }
            .frame(width: 520)
        case "AllNotesRenameSheet":
            AllNotesRenameSheet(
                title: $renameTitle,
                errorMessage: nil,
                isSaving: false,
                onCancel: {},
                onSave: {}
            )
        case "MacListSearchBar":
            MacListSearchBar(placeholder: "搜索笔记...", text: $textValue, onClose: {})
                .frame(width: 380)
        case "MacListSearchToolbarAppearance":
            VStack(spacing: DS.s3) {
                MacListSearchBar(placeholder: "搜索笔记...", text: $textValue, onClose: {})
                    .frame(width: 460)
                Text("该桥接组件正在把当前详情窗口切换为搜索工具栏外观")
                    .font(DS.caption())
                    .foregroundStyle(DS.textSecondary)
            }
            .background(MacListSearchToolbarAppearance(isActive: true))
        case "TrashView":
            TrashView()
                .frame(width: 660, height: 560)
        case "TrashListRow":
            TrashListRow(
                title: "已删除的加密笔记",
                subtitle: "昨天删除 · 29 天后永久删除"
            ) {
                HStack(spacing: DS.s2) {
                    SWStatusBadge("加密", systemImage: "lock.fill", style: .neutral)
                    SWStatusBadge("剩 29 天", systemImage: "clock", style: .warning)
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
                    body: "# Markdown 编辑器\n\n这是悬浮便签编辑器的真实预览。",
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                isPreview: true
            )
            .frame(width: 520, height: 440)
        case "MacTextView":
            MacTextView(
                text: $draft,
                placeholder: "随便写点什么吧",
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
                text: "# Markdown 预览\n\n- **粗体** 与 *斜体*\n- `inline code`\n\n> 这是实际的 Markdown 渲染组件。",
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
                    Text(isToolbarHovered ? "已进入工具栏感应区域" : "将指针移入此区域")
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

            Text(title)
                .font(DS.title())
                .foregroundStyle(DS.textStrong)

            Text(subtitle)
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
            Button("系统按钮") {}
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
                Text("由 NSHostingView 承载的 SwiftUI 内容")
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
