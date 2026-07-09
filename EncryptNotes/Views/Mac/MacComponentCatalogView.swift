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
        ComponentEntry(name: "Button", description: "基础点击动作、工具栏动作和表单尾部操作。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Menu", description: "更多操作、菜单栏列表和笔记上下文操作。", source: "SwiftUI / AppKit NSMenu", kind: .system),
        ComponentEntry(name: "Picker", description: "设置页分段选项和模式选择。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Toggle", description: "设置页开关项。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Slider", description: "编辑器字号、行高和透明度设置。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "TextField", description: "搜索、标题、路径和 API Key 输入。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "SecureField", description: "密钥与敏感字段输入。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "TextEditor", description: "iOS 笔记正文编辑。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "List", description: "全部笔记、回收站和设置集合。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "ScrollView", description: "设置页、关于页和组件目录滚动容器。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "LazyVStack / LazyVGrid", description: "列表、快捷键双列布局和栅格内容。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "TabView", description: "设置页分栏。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "NavigationStack", description: "iOS 页面导航。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "ProgressView", description: "导入、导出、加载等等待状态。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Image / SF Symbols", description: "图标、状态标识和按钮图形。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "Alert / Sheet / ConfirmationDialog", description: "错误、确认、编辑和导出流程。", source: "SwiftUI", kind: .system),
        ComponentEntry(name: "NSWindow", description: "便签、全部笔记、回收站、设置和组件目录窗口。", source: "AppKit", kind: .system),
        ComponentEntry(name: "NSStatusItem", description: "macOS 菜单栏入口。", source: "AppKit", kind: .system),
        ComponentEntry(name: "NSHostingView", description: "把 SwiftUI 内容承载到 macOS 窗口。", source: "AppKit", kind: .system),
        ComponentEntry(name: "NSTextView / NSScrollView", description: "macOS 便签编辑器和 Markdown 高亮编辑体验。", source: "AppKit", kind: .system)
    ]

    private static let customComponents: [ComponentEntry] = [
        ComponentEntry(name: "SWShimmer", description: "加载占位的扫光效果。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWStatusBadge", description: "状态胶囊标签。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWSectionPanel", description: "设置页和信息页的分组面板。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWPanelStack", description: "设置内容的统一竖向容器。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWPageHeader", description: "页面标题区域。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWSettingsRow", description: "设置页列表行。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWSettingsActionButton", description: "统一的设置尾部操作按钮。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWRowDivider", description: "设置列表行分割线。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWEmptyState", description: "空状态展示。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWSearchField", description: "共享搜索输入。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWFilterChip", description: "标签和过滤条件胶囊。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "SWNoteListRow", description: "iOS 和旧列表样式的笔记行基础组件。", source: "Views/Components/SWComponents.swift", kind: .custom),
        ComponentEntry(name: "NoteCardView", description: "明文笔记卡片。", source: "Views/Components/NoteCardView.swift", kind: .custom),
        ComponentEntry(name: "EncryptedCardView", description: "加密笔记卡片。", source: "Views/Components/EncryptedCardView.swift", kind: .custom),
        ComponentEntry(name: "BottomComposerView", description: "首页底部快速输入。", source: "Views/Components/BottomComposerView.swift", kind: .custom),
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
        ComponentEntry(name: "LockedStickyNoteView", description: "加密便签锁定状态内容。", source: "Views/Mac/LockedStickyNoteView.swift", kind: .custom),
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
        VStack(alignment: .leading, spacing: DS.s3) {
            Text(title)
                .font(DS.title())
                .foregroundStyle(DS.textStrong)

            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    componentRow(entry)

                    if index < entries.count - 1 {
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .resizable, .unifiedTitleAndToolbar, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = entry.name
        window.contentView = NSHostingView(rootView: MacComponentPreviewView(entry: entry))
        window.contentMinSize = NSSize(width: 440, height: 360)
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
    @State private var isEncrypted = false
    @State private var pickerValue = "明文"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s4) {
            header

            VStack(alignment: .leading, spacing: DS.s3) {
                Text("预览")
                    .font(DS.title())
                    .foregroundStyle(DS.textStrong)

                previewContent
                    .frame(maxWidth: .infinity, minHeight: 190, alignment: .center)
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
        .frame(minWidth: 440, minHeight: 360)
        .background(DS.bg)
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
            HStack(spacing: DS.s2) {
                Button("系统按钮") {}
                    .buttonStyle(.bordered)
                Button("强调") {}
                    .buttonStyle(.borderedProminent)
                    .tint(DS.primary)
            }
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
            placeholderPreview(systemImage: "exclamationmark.bubble", title: "系统弹层", subtitle: "真实弹层会在业务流程中触发")
        case "NSWindow":
            placeholderPreview(systemImage: "macwindow", title: "独立窗口", subtitle: "当前预览本身就是 NSWindow")
        case "NSStatusItem":
            placeholderPreview(systemImage: "menubar.rectangle", title: "菜单栏入口", subtitle: "显示在 macOS 菜单栏")
        case "NSHostingView":
            placeholderPreview(systemImage: "rectangle.on.rectangle", title: "SwiftUI 承载", subtitle: "把 SwiftUI 放入 AppKit 窗口")
        case "NSTextView / NSScrollView":
            VStack(alignment: .leading, spacing: DS.s2) {
                Text("# Markdown")
                    .font(DS.title())
                    .foregroundStyle(DS.primary)
                Text("- 高亮语法\n- 自动滚动\n- 原生选择体验")
                    .font(DS.body())
                    .foregroundStyle(DS.textBody)
            }
            .frame(maxWidth: 300, alignment: .leading)
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
        case "SWSettingsActionButton":
            HStack(spacing: DS.s2) {
                SWSettingsActionButton(.icon(systemImage: "arrow.up.right")) {}
                SWSettingsActionButton(.iconText(systemImage: "folder", title: "打开"), style: .light) {}
                SWSettingsActionButton(.text("保存"), style: .fill) {}
            }
        case "SWRowDivider":
            VStack(spacing: 0) {
                SWSettingsRow("上一行", systemImage: "1.circle") { EmptyView() }
                SWRowDivider()
                SWSettingsRow("下一行", systemImage: "2.circle") { EmptyView() }
            }
            .frame(width: 360)
        case "SWEmptyState":
            SWEmptyState(title: "暂无内容", message: "内容会在这里显示。", systemImage: "tray")
        case "SWSearchField":
            SWSearchField(placeholder: "搜索笔记", text: $textValue)
                .frame(width: 280)
        case "SWFilterChip":
            HStack(spacing: DS.s2) {
                SWFilterChip(title: "全部", isSelected: true) {}
                SWFilterChip(title: "工作", isSelected: false) {}
            }
        case "SWNoteListRow":
            SWNoteListRow(title: "Seal Note 迭代记录", subtitle: "组件预览示例", systemImage: "doc.text") {
                Text("刚刚")
                    .font(DS.caption())
                    .foregroundStyle(DS.textSubtle)
            }
            .frame(width: 360)
        case "BottomComposerView":
            BottomComposerView(draft: $draft, isEncrypted: $isEncrypted, canEncrypt: true, isSaving: false, onSubmit: {}, onExpand: {})
                .frame(width: 380)
        case "MacListSearchBar":
            MacListSearchBar(placeholder: "搜索笔记...", text: $textValue, onClose: {})
                .frame(width: 380)
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
#endif
