import Combine
import Foundation

struct NoteTab: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date
    var selectionLocation: Int?
    var selectionLength: Int?
    var filePath: String?

    init(id: UUID = UUID(), text: String = "", createdAt: Date = Date(), filePath: String? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.filePath = filePath
        selectionLocation = 0
        selectionLength = 0
    }

    var fileURL: URL? {
        filePath.map { URL(fileURLWithPath: $0) }
    }

    var fileName: String {
        fileURL?.lastPathComponent ?? "\(title).md"
    }

    var title: String {
        Self.firstHeadingTitle(in: text)
            ?? fileURL?.deletingPathExtension().lastPathComponent
            ?? "Untitled"
    }

    static func firstHeadingTitle(in text: String) -> String? {
        guard let firstLine = text.components(separatedBy: .newlines).first else { return nil }
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("# ") else { return nil }

        let title = trimmed
            .dropFirst(2)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? nil : title
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var tabs: [NoteTab]
    @Published private(set) var activeTabID: UUID
    @Published var searchQuery = ""

    private static let legacyTextKey = "notchNotes.text"
    private static let activeFilePathKey = "notchNotes.activeFilePath"
    private let markdownRoot = WorkspacePaths.markdownRoot
    private var syncTimer: Timer?
    private var isWritingToDisk = false

    init() {
        WorkspacePaths.ensureDirectories()

        var initialTabs = Self.loadMarkdownTabs(from: markdownRoot)
        if initialTabs.isEmpty {
            let legacyText = UserDefaults.standard.string(forKey: Self.legacyTextKey)
            let seededText = legacyText?.isEmpty == false ? legacyText! : "# Untitled\n\n"
            let tab = NoteTab(text: seededText)
            initialTabs = [Self.persistNewTab(tab, in: markdownRoot)]
        }

        tabs = initialTabs

        let activePath = UserDefaults.standard.string(forKey: Self.activeFilePathKey)
        activeTabID = activePath.flatMap { path in
            initialTabs.first(where: { $0.filePath == path })?.id
        } ?? initialTabs[0].id

        save()
        startDiskSync()
    }

    var text: String {
        tabs[activeIndex].text
    }

    var activeTab: NoteTab {
        tabs[activeIndex]
    }

    var filteredTabs: [NoteTab] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tabs }

        return tabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(query)
                || tab.fileName.localizedCaseInsensitiveContains(query)
        }
    }

    func updateText(_ nextText: String) {
        tabs[activeIndex].text = nextText
        clampSelection(for: tabs[activeIndex].id)
        persistActiveTabToDisk(allowRename: true)
        save()
    }

    func clear() {
        updateText("")
        updateSelection(for: activeTabID, range: NSRange(location: 0, length: 0))
    }

    func addTab() {
        let tab = Self.persistNewTab(NoteTab(text: "# Untitled\n\n"), in: markdownRoot)
        tabs.append(tab)
        activeTabID = tab.id
        searchQuery = ""
        save()
    }

    func removeActiveTab() {
        guard tabs.count > 1 else { return }
        let removedIndex = activeIndex
        tabs.remove(at: removedIndex)
        let nextIndex = min(removedIndex, tabs.count - 1)
        activeTabID = tabs[nextIndex].id
        save()
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        save()
    }

    func updateSelection(for id: UUID, range: NSRange) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let clamped = clampedRange(range, text: tabs[index].text)
        tabs[index].selectionLocation = clamped.location
        tabs[index].selectionLength = clamped.length
        save()
    }

    func selectionRange(for id: UUID) -> NSRange {
        guard let tab = tabs.first(where: { $0.id == id }) else {
            return NSRange(location: 0, length: 0)
        }

        return clampedRange(
            NSRange(location: tab.selectionLocation ?? 0, length: tab.selectionLength ?? 0),
            text: tab.text
        )
    }

    func syncFromDisk() {
        guard !isWritingToDisk else { return }
        let diskTabs = Self.loadMarkdownTabs(from: markdownRoot)

        if diskTabs.isEmpty {
            let tab = Self.persistNewTab(NoteTab(text: "# Untitled\n\n"), in: markdownRoot)
            tabs = [tab]
            activeTabID = tab.id
            save()
            return
        }

        let existingByPath = Dictionary(uniqueKeysWithValues: tabs.compactMap { tab -> (String, NoteTab)? in
            guard let filePath = tab.filePath else { return nil }
            return (filePath, tab)
        })

        let mergedTabs = diskTabs.map { diskTab -> NoteTab in
            guard var existing = diskTab.filePath.flatMap({ existingByPath[$0] }) else {
                return diskTab
            }

            existing.text = diskTab.text
            existing.createdAt = diskTab.createdAt
            return existing
        }

        guard mergedTabs != tabs else { return }

        let activePath = activeTab.filePath
        tabs = mergedTabs
        if let activePath,
           let activeID = mergedTabs.first(where: { $0.filePath == activePath })?.id {
            activeTabID = activeID
        } else {
            activeTabID = mergedTabs[0].id
        }
        save()
    }

    private var activeIndex: Int {
        tabs.firstIndex { $0.id == activeTabID } ?? 0
    }

    private func persistActiveTabToDisk(allowRename: Bool) {
        guard tabs.indices.contains(activeIndex) else { return }
        isWritingToDisk = true
        defer { isWritingToDisk = false }

        var tab = tabs[activeIndex]
        let currentURL = tab.fileURL
        let directoryURL = currentURL?.deletingLastPathComponent() ?? markdownRoot
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let desiredURL: URL
        if allowRename, let title = NoteTab.firstHeadingTitle(in: tab.text) {
            desiredURL = WorkspacePaths.uniquedFileURL(
                stem: title,
                fileExtension: "md",
                in: directoryURL,
                excluding: currentURL
            )
        } else if let currentURL {
            desiredURL = currentURL
        } else {
            desiredURL = WorkspacePaths.uniquedFileURL(
                stem: tab.title,
                fileExtension: "md",
                in: markdownRoot
            )
        }

        if let currentURL,
           currentURL.standardizedFileURL.path != desiredURL.standardizedFileURL.path,
           FileManager.default.fileExists(atPath: currentURL.path) {
            try? FileManager.default.moveItem(at: currentURL, to: desiredURL)
        }

        do {
            try tab.text.write(to: desiredURL, atomically: true, encoding: .utf8)
            tab.filePath = desiredURL.path
            tabs[activeIndex] = tab
        } catch {
            tabs[activeIndex] = tab
        }
    }

    private func clampSelection(for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let range = NSRange(location: tabs[index].selectionLocation ?? 0, length: tabs[index].selectionLength ?? 0)
        let clamped = clampedRange(range, text: tabs[index].text)
        tabs[index].selectionLocation = clamped.location
        tabs[index].selectionLength = clamped.length
    }

    private func clampedRange(_ range: NSRange, text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(range.location, 0), length)
        let selectionLength = min(max(range.length, 0), length - location)
        return NSRange(location: location, length: selectionLength)
    }

    private func save() {
        if let activePath = activeTab.filePath {
            UserDefaults.standard.set(activePath, forKey: Self.activeFilePathKey)
        }
        UserDefaults.standard.set(text, forKey: Self.legacyTextKey)
    }

    private func startDiskSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromDisk()
            }
        }
    }

    private static func loadMarkdownTabs(from root: URL) -> [NoteTab] {
        let manager = FileManager.default
        try? manager.createDirectory(at: root, withIntermediateDirectories: true)
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var loadedTabs: [NoteTab] = []

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            if values?.isDirectory == true {
                if url.lastPathComponent == "attachments" {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard ["md", "markdown"].contains(url.pathExtension.lowercased()) else { continue }
            let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url))
                ?? ""
            loadedTabs.append(
                NoteTab(
                    text: text,
                    createdAt: values?.contentModificationDate ?? Date(),
                    filePath: url.path
                )
            )
        }

        return loadedTabs.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }

    private static func persistNewTab(_ tab: NoteTab, in root: URL) -> NoteTab {
        var nextTab = tab
        let title = NoteTab.firstHeadingTitle(in: tab.text) ?? "Untitled"
        let url = WorkspacePaths.uniquedFileURL(stem: title, fileExtension: "md", in: root)
        try? tab.text.write(to: url, atomically: true, encoding: .utf8)
        nextTab.filePath = url.path
        return nextTab
    }
}
