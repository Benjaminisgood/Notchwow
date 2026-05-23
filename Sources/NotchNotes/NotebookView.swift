import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SwiftUI

@MainActor
final class DrawerState: ObservableObject {
    @Published var isExpanded = false
    @Published var revealProgress: CGFloat = 0
}

struct NotebookView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var drawerState: DrawerState
    @ObservedObject var editorInteractionState: EditorInteractionState
    @ObservedObject var workbenchState: WorkbenchState
    @ObservedObject var pythonStore: CodeFileStore
    @ObservedObject var shellCommandStore: ShellCommandStore
    @ObservedObject var terminalTaskStore: TerminalTaskStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var terminalRunner: CommandRunner
    @ObservedObject var pythonRunner: CommandRunner
    let layout: NotchLayout
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            drawer
        }
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
    }

    private var drawer: some View {
        ZStack(alignment: .top) {
            expandedContent
                .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .opacity(expandedContentOpacity)

            compactIcon
        }
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
        .background(Color(red: 0.02, green: 0.02, blue: 0.025).opacity(0.98))
        .mask(alignment: .top) {
            TopAttachedRoundedShape(radius: cornerRadius)
                .frame(width: revealWidth, height: revealHeight)
        }
        .overlay(alignment: .top) {
            TopAttachedRoundedShape(radius: cornerRadius)
                .stroke(.white.opacity(0.09), lineWidth: 1)
                .frame(width: revealWidth, height: revealHeight)
        }
        .contentShape(Rectangle())
        .allowsHitTesting(drawerState.isExpanded)
    }

    private var expandedContent: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    WorkbenchModeControl(workbenchState: workbenchState)

                    Spacer()

                    WorkbenchTopToolsView(
                        workbenchState: workbenchState,
                        noteStore: store,
                        editorInteractionState: editorInteractionState,
                        pythonStore: pythonStore,
                        shellCommandStore: shellCommandStore,
                        terminalTaskStore: terminalTaskStore,
                        terminalRunner: terminalRunner,
                        pythonRunner: pythonRunner
                    )

                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(DarkIconButtonStyle())
                    .help("Settings")
                }
                .frame(height: toolbarHeight, alignment: .center)

                WorkbenchContentView(
                    workbenchState: workbenchState,
                    store: store,
                    imageStore: imageStore,
                    editorInteractionState: editorInteractionState,
                    pythonStore: pythonStore,
                    terminalTaskStore: terminalTaskStore,
                    condaStore: condaStore,
                    terminalRunner: terminalRunner,
                    pythonRunner: pythonRunner,
                    size: workspaceSize
                )
                .frame(width: workspaceSize.width, height: workspaceSize.height)
                .background(Color(red: 0.06, green: 0.06, blue: 0.07))
            }
        }
        .padding(.top, toolbarTopPadding)
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.bottom, contentBottomPadding)
        .onAppear {
            editorInteractionState.onSelectionChange = { [weak store] range in
                guard let store else { return }
                store.updateSelection(for: store.activeTabID, range: range)
            }
            editorInteractionState.restoreSelection(store.selectionRange(for: store.activeTabID))
        }
        .onChange(of: store.activeTabID) { _, newTabID in
            editorInteractionState.restoreSelection(store.selectionRange(for: newTabID))
            editorInteractionState.requestLayoutRefresh(resetScroll: false)
        }
        .onChange(of: workbenchState.activeMode) { _, mode in
            guard mode == .markdown else { return }
            editorInteractionState.restoreSelection(store.selectionRange(for: store.activeTabID))
            editorInteractionState.requestLayoutRefresh(resetScroll: false)
        }
    }

    private var compactIcon: some View {
        Image(systemName: "note.text")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: layout.compactSize.width, height: layout.compactSize.height)
            .opacity(1 - drawerState.revealProgress)
    }

    private var revealWidth: CGFloat {
        interpolate(from: layout.compactSize.width, to: layout.expandedSize.width)
    }

    private var revealHeight: CGFloat {
        interpolate(from: layout.compactSize.height, to: layout.expandedSize.height)
    }

    private var cornerRadius: CGFloat {
        interpolate(from: 12, to: 18)
    }

    private var expandedContentOpacity: CGFloat {
        let progress = drawerState.revealProgress
        return min(max((progress - 0.42) / 0.34, 0), 1)
    }

    private var workspaceSize: CGSize {
        CGSize(
            width: layout.expandedSize.width - contentHorizontalPadding * 2,
            height: layout.expandedSize.height - toolbarTopPadding - contentBottomPadding - toolbarHeight - contentSpacing
        )
    }

    private var toolbarTopPadding: CGFloat {
        layout.compactSize.height + 6
    }

    private var contentHorizontalPadding: CGFloat {
        18
    }

    private var contentBottomPadding: CGFloat {
        18
    }

    private var toolbarHeight: CGFloat {
        28
    }

    private var contentSpacing: CGFloat {
        10
    }

    private func interpolate(from start: CGFloat, to end: CGFloat) -> CGFloat {
        start + (end - start) * drawerState.revealProgress
    }
}

struct MarkdownEditorPanel: View {
    @ObservedObject var store: NoteStore
    let imageStore: LocalImageStore
    let editorInteractionState: EditorInteractionState
    let size: CGSize

    private let toolbarHeight: CGFloat = 34
    private let separatorHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            MarkdownNoteEditor(
                store: store,
                imageStore: imageStore,
                editorInteractionState: editorInteractionState
            )
            .frame(width: size.width, height: editorHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            MarkdownShortcutToolbar(editorInteractionState: editorInteractionState)
                .frame(width: size.width, height: toolbarHeight)
                .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - toolbarHeight - separatorHeight, 120)
    }
}

struct WorkbenchModeControl: View {
    @ObservedObject var workbenchState: WorkbenchState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(WorkbenchMode.allCases) { mode in
                let isSelected = mode == workbenchState.activeMode
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        workbenchState.select(mode)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.systemImage)
                            .frame(width: 15)
                        Text(mode.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(height: 26)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(WorkbenchModeButtonStyle(isSelected: isSelected))
                .help(mode.title)
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.045))
        )
    }
}

struct WorkbenchTopToolsView: View {
    @ObservedObject var workbenchState: WorkbenchState
    @ObservedObject var noteStore: NoteStore
    let editorInteractionState: EditorInteractionState
    @ObservedObject var pythonStore: CodeFileStore
    @ObservedObject var shellCommandStore: ShellCommandStore
    @ObservedObject var terminalTaskStore: TerminalTaskStore
    @ObservedObject var terminalRunner: CommandRunner
    @ObservedObject var pythonRunner: CommandRunner

    var body: some View {
        Group {
            switch workbenchState.activeMode {
            case .markdown:
                MarkdownTopToolsView(
                    store: noteStore,
                    editorInteractionState: editorInteractionState
                )
            case .terminal:
                ShellTopToolsView(
                    commandStore: shellCommandStore,
                    runner: terminalRunner
                )
            case .python:
                PythonTopToolsView(
                    codeStore: pythonStore,
                    runner: pythonRunner
                )
            case .tasks:
                TerminalTopToolsView(
                    taskStore: terminalTaskStore
                )
            }
        }
        .frame(maxWidth: 600, alignment: .trailing)
    }
}

struct MarkdownTopToolsView: View {
    @ObservedObject var store: NoteStore
    let editorInteractionState: EditorInteractionState
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: store.activeTab.title,
                detail: store.activeTab.fileName,
                systemImage: "doc.text"
            )

            ToolbarSearchBox(
                placeholder: "md",
                query: $store.searchQuery,
                resultCount: store.filteredTabs.count,
                isShowingResults: $isShowingSearchResults
            ) {
                Button {
                    store.syncFromDisk()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Sync Markdown")

                Button {
                    rememberCurrentSelection()
                    store.addTab()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("New Markdown")

                Button {
                    store.clear()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Clear current Markdown")
            } results: {
                MarkdownSearchResultsPopover(
                    tabs: Array(store.filteredTabs.prefix(32)),
                    activeTabID: store.activeTabID
                ) { tab in
                    rememberCurrentSelection()
                    store.selectTab(tab.id)
                    store.searchQuery = ""
                    isShowingSearchResults = false
                }
            }
        }
    }

    private func rememberCurrentSelection() {
        guard let range = editorInteractionState.currentSelectionRange() else { return }
        store.updateSelection(for: store.activeTabID, range: range)
    }
}

struct PythonTopToolsView: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var runner: CommandRunner
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: codeStore.activeFile.fileName,
                detail: codeStore.activeFile.filePath,
                systemImage: "curlybraces.square"
            )

            ToolbarSearchBox(
                placeholder: "py",
                query: $codeStore.searchQuery,
                resultCount: codeStore.filteredFiles.count,
                isShowingResults: $isShowingSearchResults
            ) {
                Button {
                    codeStore.syncFromDisk()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Sync Python")

                Button {
                    codeStore.addFile()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("New Python file")

                Button {
                    runner.clear()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Clear Python output")
            } results: {
                CodeSearchResultsPopover(
                    files: Array(codeStore.filteredFiles.prefix(32)),
                    activeFileID: codeStore.activeFileID
                ) { file in
                    codeStore.selectFile(file.id)
                    codeStore.searchQuery = ""
                    isShowingSearchResults = false
                }
            }
        }
    }
}

struct ShellTopToolsView: View {
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var runner: CommandRunner
    @State private var commandQuery = ""
    @State private var isShowingSearchResults = false

    private var filteredCommands: [ShellCommandItem] {
        commandStore.filteredCommands(matching: commandQuery)
    }

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: runner.input.isEmpty ? "Shell session" : runner.input,
                detail: runner.storagePath,
                systemImage: "dollarsign.square"
            )

            ToolbarSearchBox(
                placeholder: "shell",
                query: $commandQuery,
                resultCount: filteredCommands.count,
                isShowingResults: $isShowingSearchResults
            ) {
                Button {
                    commandStore.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Refresh Benshell commands")

                Button {
                    NSWorkspace.shared.open(WorkspacePaths.shellRoot)
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Open Shell storage")

                Button {
                    runner.clear()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Clear Shell output")
            } results: {
                ShellSearchResultsPopover(
                    commands: Array(filteredCommands.prefix(40)),
                    activeCommand: runner.input,
                    isRunning: runner.isRunning
                ) { item in
                    runner.input = item.command
                    runner.run(item.command)
                    commandQuery = ""
                    isShowingSearchResults = false
                }
            }
        }
    }
}

struct TerminalTopToolsView: View {
    @ObservedObject var taskStore: TerminalTaskStore
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: taskStore.selectedTask?.title ?? "Terminal tasks",
                detail: taskStore.selectedTask?.detail ?? "\(taskStore.tasks.count) tasks",
                systemImage: "terminal.fill"
            )

            ToolbarSearchBox(
                placeholder: "term",
                query: $taskStore.searchQuery,
                resultCount: taskStore.filteredTasks.count,
                isShowingResults: $isShowingSearchResults
            ) {
                Button {
                    taskStore.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Refresh terminal tasks")

                Button {
                    taskStore.refreshSelectedTerminalSnapshot()
                } label: {
                    Image(systemName: "text.viewfinder")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(taskStore.selectedTask == nil || taskStore.isTerminalBridgeBusy)
                .help("Refresh Terminal contents")

                Button {
                    taskStore.focusSelectedTerminal()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(taskStore.selectedTask == nil || taskStore.isTerminalBridgeBusy)
                .help("Focus Terminal tab")

                Button {
                    taskStore.openTerminal()
                } label: {
                    Image(systemName: "macwindow")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Open Terminal")
            } results: {
                TerminalTaskSearchResultsPopover(
                    tasks: Array(taskStore.filteredTasks.prefix(40)),
                    selectedTaskID: taskStore.selectedTask?.id
                ) { task in
                    taskStore.select(task)
                    taskStore.searchQuery = ""
                    isShowingSearchResults = false
                }
            }
        }
    }
}

struct TerminalTaskSearchResultsPopover: View {
    let tasks: [TerminalTask]
    let selectedTaskID: TerminalTask.ID?
    let onSelect: (TerminalTask) -> Void

    var body: some View {
        SearchResultsContainer {
            if tasks.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(tasks) { task in
                    Button {
                        onSelect(task)
                    } label: {
                        SearchResultRow(
                            systemImage: task.systemImage,
                            title: task.title,
                            detail: task.detail
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: task.id == selectedTaskID))
                    .help(task.title)
                }
            }
        }
    }
}

struct ToolbarSearchBox<Actions: View, Results: View>: View {
    let placeholder: String
    @Binding var query: String
    let resultCount: Int
    @Binding var isShowingResults: Bool
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let results: () -> Results

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var isExpanded: Bool {
        isHovering || isFocused || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 16, height: 22)

            if isExpanded {
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                    .focused($isFocused)
                    .onChange(of: query) { _, nextQuery in
                        isShowingResults = !nextQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }

                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("\(resultCount)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(minWidth: 22, alignment: .trailing)
                }

                actions()
            }
        }
        .padding(.horizontal, isExpanded ? 8 : 6)
        .frame(width: isExpanded ? 300 : 28, height: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(isExpanded ? 0.055 : 0.035))
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .popover(isPresented: $isShowingResults, arrowEdge: .bottom) {
            results()
        }
    }
}

struct WorkbenchContentView: View {
    @ObservedObject var workbenchState: WorkbenchState
    @ObservedObject var store: NoteStore
    let imageStore: LocalImageStore
    let editorInteractionState: EditorInteractionState
    @ObservedObject var pythonStore: CodeFileStore
    @ObservedObject var terminalTaskStore: TerminalTaskStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var terminalRunner: CommandRunner
    @ObservedObject var pythonRunner: CommandRunner
    let size: CGSize

    var body: some View {
        Group {
            switch workbenchState.activeMode {
            case .markdown:
                MarkdownWorkspaceView(
                    store: store,
                    imageStore: imageStore,
                    editorInteractionState: editorInteractionState,
                    size: size
                )
            case .terminal:
                ShellPane(runner: terminalRunner, size: size)
            case .python:
                PythonWorkspaceView(
                    codeStore: pythonStore,
                    condaStore: condaStore,
                    runner: pythonRunner,
                    size: size
                )
            case .tasks:
                TerminalTasksPane(taskStore: terminalTaskStore, size: size)
            }
        }
    }
}

struct MarkdownWorkspaceView: View {
    @ObservedObject var store: NoteStore
    let imageStore: LocalImageStore
    let editorInteractionState: EditorInteractionState
    let size: CGSize

    var body: some View {
        MarkdownEditorPanel(
            store: store,
            imageStore: imageStore,
            editorInteractionState: editorInteractionState,
            size: size
        )
        .frame(width: size.width, height: size.height)
    }
}

struct MarkdownFileBar: View {
    @ObservedObject var store: NoteStore
    let editorInteractionState: EditorInteractionState
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 16)

            TextField("filename", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(.white.opacity(0.88))
                .font(.system(size: 12))
                .onChange(of: store.searchQuery) { _, query in
                    isShowingSearchResults = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

            if !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(store.filteredTabs.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(minWidth: 22, alignment: .trailing)
            }

            ActiveFileBadge(
                title: store.activeTab.title,
                detail: store.activeTab.fileName,
                systemImage: "doc.text"
            )

            Button {
                store.syncFromDisk()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("Sync")

            Button {
                rememberCurrentSelection()
                store.addTab()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("New file")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.045))
        )
        .popover(isPresented: $isShowingSearchResults, arrowEdge: .bottom) {
            MarkdownSearchResultsPopover(
                tabs: Array(store.filteredTabs.prefix(32)),
                activeTabID: store.activeTabID
            ) { tab in
                rememberCurrentSelection()
                store.selectTab(tab.id)
                store.searchQuery = ""
                isShowingSearchResults = false
            }
        }
    }

    private func rememberCurrentSelection() {
        guard let range = editorInteractionState.currentSelectionRange() else { return }
        store.updateSelection(for: store.activeTabID, range: range)
    }
}

struct MarkdownSearchResultsPopover: View {
    let tabs: [NoteTab]
    let activeTabID: UUID
    let onSelect: (NoteTab) -> Void

    var body: some View {
        SearchResultsContainer {
            if tabs.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(tabs) { tab in
                    Button {
                        onSelect(tab)
                    } label: {
                        SearchResultRow(
                            systemImage: tab.id == activeTabID ? "doc.text.fill" : "doc.text",
                            title: tab.title,
                            detail: tab.fileName
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: tab.id == activeTabID))
                    .help(tab.fileName)
                }
            }
        }
    }
}

struct PythonWorkspaceView: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var runner: CommandRunner
    let size: CGSize

    private let outputHeight: CGFloat = 132
    private let toolbarHeight: CGFloat = 34
    private let separatorHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: Binding(
                get: { codeStore.text },
                set: { codeStore.updateText($0) }
            ))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.045, green: 0.047, blue: 0.055))
            .frame(width: size.width, height: editorHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            OutputView(output: runner.output)
                .frame(width: size.width, height: outputHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            PythonCommandToolbar(
                codeStore: codeStore,
                condaStore: condaStore,
                runner: runner
            )
            .frame(width: size.width, height: toolbarHeight)
            .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - outputHeight - toolbarHeight - separatorHeight * 2, 120)
    }
}

struct PythonCommandToolbar: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var runner: CommandRunner

    var body: some View {
        HStack(spacing: 8) {
            Text(condaStore.selectedEnvironmentName)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .frame(maxWidth: 86, alignment: .leading)

            TextField("python command", text: $runner.input)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.84))
                .onSubmit(runInputCommand)

            Button {
                runActiveFile()
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(runner.isRunning)
            .help("Run file in selected environment")

            Button {
                runInputCommand()
            } label: {
                Image(systemName: "terminal")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(runner.isRunning)
            .help("Run command in selected environment")

            Button {
                runner.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(!runner.isRunning)
            .help("Stop")
        }
        .padding(.horizontal, 10)
    }

    private func runActiveFile() {
        runner.run(
            condaStore.runPythonFileCommand(filePath: codeStore.activeFile.filePath),
            displayCommand: condaStore.runPythonFileDisplayCommand(filePath: codeStore.activeFile.filePath),
            displayPrompt: "py file>",
            showsSuccessfulExit: false
        )
    }

    private func runInputCommand() {
        guard let runCommand = condaStore.pythonConsoleCommand(runner.input) else { return }

        runner.run(
            runCommand.command,
            displayCommand: runCommand.displayCommand,
            displayPrompt: runCommand.displayPrompt,
            clearsInputOnRun: true,
            showsSuccessfulExit: false
        )
    }
}

struct EnvironmentPicker: View {
    @ObservedObject var condaStore: CondaEnvironmentStore

    var body: some View {
        Menu {
            ForEach(condaStore.environments) { environment in
                Button {
                    condaStore.select(environment.name)
                } label: {
                    HStack {
                        Text(environment.displayName)
                        if environment.name == condaStore.selectedEnvironmentName {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if condaStore.environments.isEmpty {
                Text(condaStore.lastError ?? "No conda environments")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox")
                    .frame(width: 14)
                Text(condaStore.selectedEnvironmentName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .frame(height: 24)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(FilePillButtonStyle(isSelected: false))
        .help("Conda environment")
    }
}

struct CodeFileBar: View {
    @ObservedObject var codeStore: CodeFileStore
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 16)

            TextField("filename", text: $codeStore.searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(.white.opacity(0.88))
                .font(.system(size: 12))
                .onChange(of: codeStore.searchQuery) { _, query in
                    isShowingSearchResults = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

            if !codeStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(codeStore.filteredFiles.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(minWidth: 22, alignment: .trailing)
            }

            ActiveFileBadge(
                title: codeStore.activeFile.fileName,
                detail: codeStore.activeFile.filePath,
                systemImage: "curlybraces.square"
            )

            Button {
                codeStore.syncFromDisk()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("Sync")

            Button {
                codeStore.addFile()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("New file")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.045))
        )
        .popover(isPresented: $isShowingSearchResults, arrowEdge: .bottom) {
            CodeSearchResultsPopover(
                files: Array(codeStore.filteredFiles.prefix(32)),
                activeFileID: codeStore.activeFileID
            ) { file in
                codeStore.selectFile(file.id)
                codeStore.searchQuery = ""
                isShowingSearchResults = false
            }
        }
    }
}

struct CodeSearchResultsPopover: View {
    let files: [CodeFile]
    let activeFileID: UUID
    let onSelect: (CodeFile) -> Void

    var body: some View {
        SearchResultsContainer {
            if files.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(files) { file in
                    Button {
                        onSelect(file)
                    } label: {
                        SearchResultRow(
                            systemImage: file.id == activeFileID ? "curlybraces.square.fill" : "curlybraces.square",
                            title: file.fileName,
                            detail: file.filePath
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: file.id == activeFileID))
                    .help(file.fileName)
                }
            }
        }
    }
}

struct ActiveFileBadge: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 14)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)

            if !detail.isEmpty, detail != title {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 0, maxWidth: 260, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.035))
        )
        .help(detail)
    }
}

struct SearchResultsContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                content
            }
            .padding(6)
        }
        .frame(width: 420, height: 280)
        .background(Color(red: 0.04, green: 0.042, blue: 0.05))
    }
}

struct SearchResultRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "return")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

struct EmptySearchResultView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 16)

            Text("No results")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))

            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .padding(.horizontal, 10)
    }
}

struct ShellPane: View {
    @ObservedObject var runner: CommandRunner
    let size: CGSize

    private let toolbarHeight: CGFloat = 34
    private let separatorHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            OutputView(output: runner.output)
                .frame(width: size.width, height: outputHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            ShellInputToolbar(runner: runner)
                .frame(width: size.width, height: toolbarHeight)
                .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
    }

    private var outputHeight: CGFloat {
        max(size.height - toolbarHeight - separatorHeight, 140)
    }
}

struct ShellInputToolbar: View {
    @ObservedObject var runner: CommandRunner

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.square")
                .foregroundStyle(.white.opacity(0.54))
                .frame(width: 16)

            TextField("Shell command", text: $runner.input)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .onSubmit {
                    runner.run()
                }

            Button {
                runner.run()
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(runner.isRunning)
            .help("Run")

            Button {
                runner.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(!runner.isRunning)
            .help("Stop")
        }
        .padding(.horizontal, 10)
    }
}

struct ShellCommandCatalogView: View {
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var runner: CommandRunner
    @Binding var query: String
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 16)

            TextField("commands", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .onChange(of: query) { _, nextQuery in
                    isShowingSearchResults = !nextQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(filteredCommands.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(minWidth: 22, alignment: .trailing)
            }

            ActiveFileBadge(
                title: runner.input.isEmpty ? "Shell session" : runner.input,
                detail: runner.storagePath,
                systemImage: "dollarsign.square"
            )

            Button {
                commandStore.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("Refresh commands")

            Button {
                NSWorkspace.shared.open(WorkspacePaths.shellRoot)
            } label: {
                Image(systemName: "folder")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("Open Shell storage")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.045))
        )
        .popover(isPresented: $isShowingSearchResults, arrowEdge: .bottom) {
            ShellSearchResultsPopover(
                commands: Array(filteredCommands.prefix(40)),
                activeCommand: runner.input,
                isRunning: runner.isRunning
            ) { item in
                runner.input = item.command
                runner.run(item.command)
                query = ""
                isShowingSearchResults = false
            }
        }
    }

    private var filteredCommands: [ShellCommandItem] {
        commandStore.filteredCommands(matching: query)
    }
}

struct ShellSearchResultsPopover: View {
    let commands: [ShellCommandItem]
    let activeCommand: String
    let isRunning: Bool
    let onSelect: (ShellCommandItem) -> Void

    var body: some View {
        SearchResultsContainer {
            if commands.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(commands) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        SearchResultRow(
                            systemImage: item.systemImage,
                            title: item.command,
                            detail: item.summary.isEmpty ? item.group : "\(item.group)  \(item.summary)"
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: item.command == activeCommand))
                    .disabled(isRunning)
                    .help(item.command)
                }
            }
        }
    }
}

struct CommandPane: View {
    let title: String
    let systemImage: String
    @ObservedObject var runner: CommandRunner
    let size: CGSize

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.white.opacity(0.54))
                    .frame(width: 16)

                TextField(title, text: $runner.input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .onSubmit {
                        runner.run()
                    }

                Button {
                    runner.run()
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(runner.isRunning)
                .help("Run")

                Button {
                    runner.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(!runner.isRunning)
                .help("Stop")

                Button {
                    runner.clear()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Clear")
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(0.045))
            )

            OutputView(output: runner.output)
                .frame(width: size.width, height: max(size.height - 38, 120))
        }
    }
}

struct TerminalTasksPane: View {
    @ObservedObject var taskStore: TerminalTaskStore
    let size: CGSize

    private let toolbarHeight: CGFloat = 34
    private let separatorHeight: CGFloat = 1
    private let spacing: CGFloat = 8
    private let snapshotTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: spacing) {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if taskStore.filteredTasks.isEmpty {
                            EmptyTerminalTasksView()
                        } else {
                            ForEach(taskStore.filteredTasks) { task in
                                Button {
                                    taskStore.select(task)
                                } label: {
                                    TerminalTaskRow(
                                        task: task,
                                        isSelected: task.id == taskStore.selectedTask?.id
                                    )
                                }
                                .buttonStyle(FilePillButtonStyle(isSelected: task.id == taskStore.selectedTask?.id))
                                .help(task.title)
                            }
                        }
                    }
                    .padding(2)
                }
                .frame(width: max(size.width * 0.36, 250), height: contentHeight)
                .background(Color(red: 0.04, green: 0.042, blue: 0.05))

                TerminalTaskLiveDetailView(taskStore: taskStore)
                    .frame(width: max(size.width * 0.64 - spacing, 300), height: contentHeight)
            }
            .frame(width: size.width, height: contentHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            TerminalInputToolbar(taskStore: taskStore)
                .frame(width: size.width, height: toolbarHeight)
                .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
        .frame(width: size.width, height: size.height)
        .onReceive(snapshotTimer) { _ in
            if taskStore.terminalSnapshot != nil {
                taskStore.refreshSelectedTerminalSnapshot(silent: true)
            }
        }
    }

    private var contentHeight: CGFloat {
        max(size.height - toolbarHeight - separatorHeight, 160)
    }
}

struct TerminalTaskLiveDetailView: View {
    @ObservedObject var taskStore: TerminalTaskStore

    private var selectedTask: TerminalTask? {
        taskStore.selectedTask
    }

    private var outputText: String {
        if let contents = taskStore.terminalSnapshot?.contents,
           !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return contents
        }

        if let message = taskStore.terminalBridgeMessage,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message + "\n\n" + taskStore.processSummary(for: selectedTask)
        }

        return taskStore.processSummary(for: selectedTask)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: taskStore.terminalSnapshot == nil ? "list.bullet.rectangle" : "terminal.fill")
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 16)

                Text(selectedTask?.tty ?? "no tty")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.82))

                if let snapshot = taskStore.terminalSnapshot {
                    Text(snapshot.isBusy ? "busy" : "idle")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(snapshot.isBusy ? 0.66 : 0.42))
                        .lineLimit(1)

                    if !snapshot.processes.isEmpty {
                        Text(snapshot.processes)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.38))
                            .lineLimit(1)
                    }
                } else if let selectedTask {
                    Text(selectedTask.detail)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if taskStore.isTerminalBridgeBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.58)
                        .frame(width: 18, height: 18)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color(red: 0.04, green: 0.042, blue: 0.05))

            OutputView(output: outputText)
        }
    }
}

struct TerminalInputToolbar: View {
    @ObservedObject var taskStore: TerminalTaskStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.white.opacity(0.54))
                .frame(width: 16)

            TextField("Terminal command", text: $taskStore.terminalInput)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .onSubmit {
                    taskStore.runTerminalInput()
                }

            Button {
                taskStore.focusSelectedTerminal()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(taskStore.selectedTask == nil || taskStore.isTerminalBridgeBusy)
            .help("Focus Terminal tab")

            Button {
                taskStore.runTerminalInput()
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(taskStore.isTerminalBridgeBusy)
            .help("Run in Terminal")

            Button {
                taskStore.terminateSelectedTask()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(taskStore.selectedTask == nil)
            .help("Send SIGTERM to selected task group")

            Button {
                taskStore.killSelectedTask()
            } label: {
                Image(systemName: "xmark.octagon.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(taskStore.selectedTask == nil)
            .help("Force kill selected task group")
        }
        .padding(.horizontal, 10)
    }
}

struct TerminalTaskRow: View {
    let task: TerminalTask
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: task.systemImage)
                .foregroundStyle(.white.opacity(isSelected ? 0.82 : 0.56))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(isSelected ? 0.92 : 0.78))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(task.detail)
                    Text(task.elapsed)
                    Text(task.state)
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 42)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

extension TerminalTask {
    var systemImage: String {
        if isZombieOnly {
            return "exclamationmark.triangle"
        }
        if title.localizedCaseInsensitiveContains("opencode") {
            return "sparkles"
        }
        if title.localizedCaseInsensitiveContains("npm")
            || title.localizedCaseInsensitiveContains("node") {
            return "network"
        }
        if title.localizedCaseInsensitiveContains("python") {
            return "chevron.left.forwardslash.chevron.right"
        }
        return "terminal"
    }
}

struct TerminalTaskDetailView: View {
    let task: TerminalTask?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let task {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(.white.opacity(0.58))
                            .frame(width: 16)

                        Text("pgid \(task.processGroupID)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.82))

                        Text(task.tty)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    ForEach(task.processes) { process in
                        TerminalProcessRow(process: process)
                    }
                } else {
                    EmptyTerminalTasksView()
                }
            }
            .padding(2)
        }
        .background(Color(red: 0.035, green: 0.037, blue: 0.044))
    }
}

struct TerminalProcessRow: View {
    let process: TerminalProcessInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("\(process.pid)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 48, alignment: .leading)

                Text(process.state)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(process.state.contains("Z") ? 0.68 : 0.42))
                    .frame(width: 34, alignment: .leading)

                Text(process.elapsed)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))

                Spacer(minLength: 0)
            }

            Text(process.shortCommand)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.035))
        )
    }
}

struct EmptyTerminalTasksView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 16)

            Text("No terminal tasks")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))

            Spacer(minLength: 0)
        }
        .frame(height: 40)
        .padding(.horizontal, 10)
    }
}

struct TaskActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 34)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(FilePillButtonStyle(isSelected: false))
    }
}

struct OutputView: View {
    let output: String
    private let bottomID = "output-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(output.isEmpty ? " " : output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.76))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
            }
            .background(Color(red: 0.035, green: 0.037, blue: 0.044))
            .onAppear {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
            .onChange(of: output) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
    }
}

struct MarkdownShortcutToolbar: View {
    let editorInteractionState: EditorInteractionState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MarkdownCommand.allCases) { command in
                Button {
                    editorInteractionState.applyMarkdownCommand(command)
                } label: {
                    MarkdownCommandLabel(command: command)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help(command.help)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }
}

struct MarkdownCommandLabel: View {
    let command: MarkdownCommand

    var body: some View {
        switch command {
        case .bold:
            Image(systemName: "bold")
        case .italic:
            Image(systemName: "italic")
        case .strikethrough:
            Image(systemName: "strikethrough")
        case .inlineCode:
            Text("`")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
        case .link:
            Image(systemName: "link")
        case .quote:
            Image(systemName: "quote.opening")
        case .unorderedList:
            Image(systemName: "list.bullet")
        case .orderedList:
            Image(systemName: "list.number")
        case .todoList:
            Image(systemName: "checklist")
        }
    }
}

struct TabPagerControl: View {
    @ObservedObject var store: NoteStore
    let editorInteractionState: EditorInteractionState
    @Namespace private var tabAnimation

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                rememberCurrentSelection()
                withAnimation(tabSwitchAnimation) {
                    store.removeActiveTab()
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabIconButtonStyle())
            .disabled(store.tabs.count <= 1)
            .help("Remove current tab")

            HStack(spacing: 6) {
                ForEach(store.tabs) { tab in
                    let isSelected = tab.id == store.activeTabID
                    Button {
                        rememberCurrentSelection()
                        withAnimation(tabSwitchAnimation) {
                            store.selectTab(tab.id)
                        }
                    } label: {
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.82) : Color.white.opacity(0.34))
                            .frame(width: isSelected ? 20 : 6, height: 6)
                            .frame(width: 26, height: 24)
                            .contentShape(Rectangle())
                            .matchedGeometryEffect(id: tab.id, in: tabAnimation)
                            .animation(tabSwitchAnimation, value: isSelected)
                    }
                    .buttonStyle(TabDotButtonStyle(isSelected: isSelected))
                    .help("Switch tab")
                }
            }
            .frame(minWidth: 20, alignment: .center)
            .frame(height: 28, alignment: .center)

            Button {
                rememberCurrentSelection()
                withAnimation(tabSwitchAnimation) {
                    store.addTab()
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabIconButtonStyle())
            .help("New tab")
        }
        .frame(height: 28, alignment: .center)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.045))
        )
    }

    private var tabSwitchAnimation: Animation {
        .spring(response: 0.26, dampingFraction: 0.82)
    }

    private func rememberCurrentSelection() {
        guard let range = editorInteractionState.currentSelectionRange() else { return }
        store.updateSelection(for: store.activeTabID, range: range)
    }
}

struct CompactNotchView: View {
    let layout: NotchLayout

    var body: some View {
        Image(systemName: "note.text")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: layout.compactSize.width, height: layout.compactSize.height)
            .background(Color(red: 0.02, green: 0.02, blue: 0.025).opacity(0.98))
            .clipShape(TopAttachedRoundedShape(radius: 12))
            .overlay(
                TopAttachedRoundedShape(radius: 12)
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            )
            .pointingHandCursor()
    }
}

struct MarkdownNoteEditor: View {
    @ObservedObject var store: NoteStore
    let imageStore: LocalImageStore
    let editorInteractionState: EditorInteractionState
    @State private var isWikiLinkActive = false
    @State private var pendingInlineReplacement: InlineReplacementRequest?
    private static let latexRenderer = SwiftMathBridge()

    var body: some View {
        NativeTextViewWrapper(
            text: Binding(
                get: { store.text },
                set: { store.updateText($0) }
            ),
            isWikiLinkActive: $isWikiLinkActive,
            pendingInlineReplacement: $pendingInlineReplacement,
            configuration: configuration,
            fontName: "SF Pro",
            fontSize: 15,
            documentId: store.activeTabID.uuidString,
            isEditable: true,
            onPasteImage: savePastedImage
        )
        .background {
            EditorFocusBinder(state: editorInteractionState)
        }
    }

    private func savePastedImage(_ pasteboard: NSPasteboard) -> String? {
        imageStore.saveImage(from: pasteboard)
    }

    private var configuration: MarkdownEditorConfiguration {
        let theme = MarkdownEditorTheme(
            bodyText: NSColor(white: 0.92, alpha: 1),
            mutedText: NSColor(white: 0.58, alpha: 1),
            disabledText: NSColor(white: 0.38, alpha: 1),
            headingMarker: NSColor(white: 0.44, alpha: 1),
            link: NSColor.systemBlue,
            incompleteLink: NSColor.systemBlue.withAlphaComponent(0.75),
            findMatchHighlight: NSColor.systemYellow.withAlphaComponent(0.55),
            findCurrentMatchHighlight: NSColor.systemYellow,
            latexLightModeText: .white,
            latexDarkModeText: .white,
            strikethroughColor: NSColor(white: 0.62, alpha: 1)
        )

        let services = MarkdownEditorServices(
            images: imageStore,
            latex: Self.latexRenderer
        )

        return MarkdownEditorConfiguration(
            theme: theme,
            services: services,
            lists: ListStyle(indentPerLevel: 18, extraLineHeight: 1),
            imageEmbed: ImageEmbedStyle(fallbackMaxWidth: 440, paragraphSpacing: 6, imageGap: 6),
            overscroll: OverscrollPolicy(percent: 0, maxPoints: 0, minPoints: 0),
            dragSelection: DragSelectionPolicy(movementThreshold: 8, edgeTriggerDistance: 8, scrollStepPerTick: 4, ticksPerSecond: 30),
            scrollers: .vertical,
            textInsets: TextInsets(horizontal: 12, vertical: 12)
        )
    }
}

struct TopAttachedRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

struct DarkIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 13, weight: .semibold),
            normalOpacity: 0.055,
            hoverOpacity: 0.085,
            pressedOpacity: 0.12,
            strokeOpacity: 0.06,
            foregroundOpacity: 0.76,
            pressedForegroundOpacity: 0.55
        )
    }
}

struct TabIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .bold),
            normalOpacity: 0,
            hoverOpacity: 0.065,
            pressedOpacity: 0.10,
            strokeOpacity: 0,
            foregroundOpacity: 0.72,
            pressedForegroundOpacity: 0.48
        )
    }
}

struct TabDotButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .semibold),
            normalOpacity: isSelected ? 0.045 : 0,
            hoverOpacity: isSelected ? 0.075 : 0.055,
            pressedOpacity: isSelected ? 0.10 : 0.08,
            strokeOpacity: 0,
            foregroundOpacity: 0.72,
            pressedForegroundOpacity: 0.58
        )
    }
}

struct MarkdownToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .semibold),
            normalOpacity: 0,
            hoverOpacity: 0.065,
            pressedOpacity: 0.10,
            strokeOpacity: 0,
            foregroundOpacity: 0.66,
            hoverForegroundOpacity: 0.84,
            pressedForegroundOpacity: 0.54
        )
    }
}

struct WorkbenchModeButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: nil,
            normalOpacity: isSelected ? 0.14 : 0,
            hoverOpacity: isSelected ? 0.18 : 0.07,
            pressedOpacity: 0.22,
            strokeOpacity: isSelected ? 0.10 : 0,
            foregroundOpacity: isSelected ? 0.92 : 0.58,
            hoverForegroundOpacity: 0.9,
            pressedForegroundOpacity: 0.72
        )
    }
}

struct FilePillButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: nil,
            normalOpacity: isSelected ? 0.12 : 0.045,
            hoverOpacity: isSelected ? 0.16 : 0.08,
            pressedOpacity: 0.18,
            strokeOpacity: isSelected ? 0.10 : 0.04,
            foregroundOpacity: isSelected ? 0.9 : 0.68,
            hoverForegroundOpacity: 0.9,
            pressedForegroundOpacity: 0.68
        )
    }
}

private struct RoundedHoverButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let font: Font?
    let normalOpacity: CGFloat
    let hoverOpacity: CGFloat
    let pressedOpacity: CGFloat
    let strokeOpacity: CGFloat
    let foregroundOpacity: CGFloat
    let hoverForegroundOpacity: CGFloat
    let pressedForegroundOpacity: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    init(
        configuration: ButtonStyle.Configuration,
        font: Font?,
        normalOpacity: CGFloat,
        hoverOpacity: CGFloat,
        pressedOpacity: CGFloat,
        strokeOpacity: CGFloat,
        foregroundOpacity: CGFloat,
        hoverForegroundOpacity: CGFloat? = nil,
        pressedForegroundOpacity: CGFloat
    ) {
        self.configuration = configuration
        self.font = font
        self.normalOpacity = normalOpacity
        self.hoverOpacity = hoverOpacity
        self.pressedOpacity = pressedOpacity
        self.strokeOpacity = strokeOpacity
        self.foregroundOpacity = foregroundOpacity
        self.hoverForegroundOpacity = hoverForegroundOpacity ?? foregroundOpacity
        self.pressedForegroundOpacity = pressedForegroundOpacity
    }

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(.white.opacity(currentForegroundOpacity))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(currentBackgroundOpacity))
            )
            .animation(.easeOut(duration: 0.10), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
            }
            .pointingHandCursor(isEnabled: isEnabled)
    }

    private var currentBackgroundOpacity: CGFloat {
        guard isEnabled else { return 0 }
        if configuration.isPressed {
            return pressedOpacity
        }
        return isHovering ? hoverOpacity : normalOpacity
    }

    private var currentForegroundOpacity: CGFloat {
        guard isEnabled else { return 0.22 }
        if configuration.isPressed {
            return pressedForegroundOpacity
        }
        return isHovering ? hoverForegroundOpacity : foregroundOpacity
    }
}

private extension View {
    func pointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool
    @State private var isCursorActive = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, isEnabled, !isCursorActive {
                    NSCursor.pointingHand.push()
                    isCursorActive = true
                } else if (!hovering || !isEnabled), isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled, isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
            .onDisappear {
                if isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
    }
}
