import Combine
import Darwin
import Foundation

struct TerminalProcessInfo: Identifiable, Equatable, Sendable {
    let id: Int32
    let pid: Int32
    let parentPID: Int32
    let processGroupID: Int32
    let tty: String
    let state: String
    let elapsed: String
    let command: String

    var shortCommand: String {
        TerminalTaskStore.shortCommand(command)
    }
}

struct TerminalTask: Identifiable, Equatable, Sendable {
    let id: Int32
    let processGroupID: Int32
    let tty: String
    let leaderPID: Int32
    let representativePID: Int32
    let elapsed: String
    let state: String
    let title: String
    let detail: String
    let command: String
    let processes: [TerminalProcessInfo]

    var processCount: Int {
        processes.count
    }

    var isZombieOnly: Bool {
        !processes.isEmpty && processes.allSatisfy { $0.state.contains("Z") }
    }
}

@MainActor
final class TerminalTaskStore: ObservableObject {
    @Published private(set) var tasks: [TerminalTask] = []
    @Published var selectedTaskID: TerminalTask.ID?
    @Published var searchQuery = ""
    @Published var terminalInput = ""
    @Published private(set) var lastRefresh = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var terminalSnapshot: TerminalTabSnapshot?
    @Published private(set) var terminalBridgeMessage: String?
    @Published private(set) var isTerminalBridgeBusy = false

    private var refreshTimer: Timer?
    private var suggestedTerminalInput = ""

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    var selectedTask: TerminalTask? {
        guard let selectedTaskID else { return tasks.first }
        return tasks.first { $0.id == selectedTaskID } ?? tasks.first
    }

    var filteredTasks: [TerminalTask] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tasks }

        return tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(query)
                || task.detail.localizedCaseInsensitiveContains(query)
                || task.tty.localizedCaseInsensitiveContains(query)
                || task.command.localizedCaseInsensitiveContains(query)
                || task.processes.contains { process in
                    process.command.localizedCaseInsensitiveContains(query)
                }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async {
            let nextTasks = Self.loadTasks()

            Task { @MainActor in
                self.applyTasks(nextTasks)
                self.isRefreshing = false
            }
        }
    }

    private func applyTasks(_ nextTasks: [TerminalTask]) {
        let previousTaskID = selectedTaskID
        tasks = nextTasks

        if let selectedTaskID, nextTasks.contains(where: { $0.id == selectedTaskID }) {
            self.selectedTaskID = selectedTaskID
        } else {
            selectedTaskID = nextTasks.first?.id
        }

        if previousTaskID != selectedTaskID, let selectedTask {
            updateTerminalInputSuggestion(for: selectedTask)
            terminalSnapshot = nil
            terminalBridgeMessage = nil
        } else if terminalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let selectedTask {
            updateTerminalInputSuggestion(for: selectedTask)
        }

        lastRefresh = Date()
    }

    func select(_ task: TerminalTask) {
        let previousTask = selectedTask
        selectedTaskID = task.id
        updateTerminalInputSuggestion(for: task, replacingPreviousTask: previousTask)
        terminalSnapshot = nil
        terminalBridgeMessage = nil
    }

    func terminateSelectedTask() {
        guard let selectedTask else { return }
        Self.signalProcessGroup(selectedTask.processGroupID, signal: SIGTERM)
        refreshSoon()
    }

    func killSelectedTask() {
        guard let selectedTask else { return }
        Self.signalProcessGroup(selectedTask.processGroupID, signal: SIGKILL)
        refreshSoon()
    }

    func openTerminal() {
        TerminalAppBridge.openTerminal()
    }

    func openNewTerminalWindow() {
        runTerminalBridgeOperation {
            TerminalAppBridge.openNewWindow(workingDirectory: WorkspacePaths.root.path)
        } completion: { [weak self] result in
            switch result {
            case .success:
                self?.terminalBridgeMessage = nil
                self?.refreshSoon()
            case .failure(let message):
                self?.terminalBridgeMessage = message
                self?.refreshSoon()
            }
        }
    }

    func focusSelectedTerminal() {
        guard let selectedTask else {
            TerminalAppBridge.openTerminal()
            return
        }

        let tty = selectedTask.tty
        runTerminalBridgeOperation {
            TerminalAppBridge.focus(tty: tty)
        } completion: { [weak self] result in
            switch result {
            case .success:
                self?.terminalBridgeMessage = nil
            case .failure(let message):
                self?.terminalSnapshot = nil
                self?.terminalBridgeMessage = message
            }
        }
    }

    func refreshSelectedTerminalSnapshot(silent: Bool = false) {
        guard let selectedTask else {
            terminalSnapshot = nil
            terminalBridgeMessage = "No terminal task selected"
            return
        }

        let taskID = selectedTask.id
        let tty = selectedTask.tty

        runTerminalBridgeOperation {
            TerminalAppBridge.snapshot(forTTY: tty)
        } completion: { [weak self] result in
            guard let self else { return }
            guard self.selectedTaskID == nil || self.selectedTaskID == taskID else { return }

            switch result {
            case .success(let snapshot):
                self.terminalSnapshot = snapshot
                self.terminalBridgeMessage = nil

            case .failure(let message):
                self.terminalSnapshot = nil
                if !silent || self.terminalBridgeMessage == nil {
                    self.terminalBridgeMessage = message
                }
            }
        }
    }

    func runTerminalInput() {
        let command = terminalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            focusSelectedTerminal()
            return
        }

        let task = selectedTask
        let tty = task?.tty
        let taskID = task?.id
        let representativePID = task?.representativePID

        runTerminalBridgeOperation {
            let workingDirectory = representativePID.flatMap(Self.workingDirectory(for:))
            return TerminalAppBridge.run(command: command, tty: tty, workingDirectory: workingDirectory)
        } completion: { [weak self] result in
            guard let self else { return }

            switch result {
            case .success:
                self.terminalBridgeMessage = nil
                self.refreshSoon()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self else { return }
                    if taskID == nil || self.selectedTaskID == taskID {
                        self.refreshSelectedTerminalSnapshot(silent: true)
                    }
                }

            case .failure(let message):
                self.terminalBridgeMessage = message
            }
        }
    }

    func clearTerminalSnapshot() {
        terminalSnapshot = nil
        terminalBridgeMessage = nil
    }

    func processSummary(for task: TerminalTask?) -> String {
        guard let task else { return "No terminal task selected" }

        return task.processes.map { process in
            "\(process.pid)  \(process.state)  \(process.elapsed)\n\(process.shortCommand)"
        }
        .joined(separator: "\n\n")
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }

    private func updateTerminalInputSuggestion(
        for task: TerminalTask,
        replacingPreviousTask previousTask: TerminalTask? = nil
    ) {
        let command = task.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        let currentInput = terminalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousCommand = previousTask?.command.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentInput.isEmpty || currentInput == suggestedTerminalInput || currentInput == previousCommand {
            terminalInput = command
            suggestedTerminalInput = command
        }
    }

    private func runTerminalBridgeOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () -> TerminalBridgeResult<Value>,
        completion: @escaping @MainActor (TerminalBridgeResult<Value>) -> Void
    ) {
        guard !isTerminalBridgeBusy else { return }
        isTerminalBridgeBusy = true

        DispatchQueue.global(qos: .utility).async {
            let result = operation()

            Task { @MainActor in
                self.isTerminalBridgeBusy = false
                completion(result)
            }
        }
    }

    private nonisolated static func loadTasks() -> [TerminalTask] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,pgid=,tty=,stat=,etime=,command="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return [] }

        let output = String(data: data, encoding: .utf8) ?? ""
        let processes = output
            .components(separatedBy: .newlines)
            .compactMap(parseProcessLine)
            .filter { $0.tty != "??" }

        let grouped = Dictionary(grouping: processes, by: \.processGroupID)

        return grouped.values
            .compactMap(makeTask)
            .sorted { lhs, rhs in
                if lhs.tty == rhs.tty {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.tty.localizedStandardCompare(rhs.tty) == .orderedAscending
            }
    }

    private nonisolated static func parseProcessLine(_ line: String) -> TerminalProcessInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed
            .split(maxSplits: 6, omittingEmptySubsequences: true) { $0 == " " || $0 == "\t" }
            .map(String.init)
        guard parts.count >= 7,
              let pid = Int32(parts[0]),
              let parentPID = Int32(parts[1]),
              let processGroupID = Int32(parts[2]) else {
            return nil
        }

        return TerminalProcessInfo(
            id: pid,
            pid: pid,
            parentPID: parentPID,
            processGroupID: processGroupID,
            tty: parts[3],
            state: parts[4],
            elapsed: parts[5],
            command: parts[6]
        )
    }

    private nonisolated static func makeTask(from processes: [TerminalProcessInfo]) -> TerminalTask? {
        guard !processes.isEmpty else { return nil }

        let sortedProcesses = processes.sorted { lhs, rhs in
            if lhs.pid == lhs.processGroupID { return true }
            if rhs.pid == rhs.processGroupID { return false }
            return lhs.pid < rhs.pid
        }

        let leader = sortedProcesses.first { $0.pid == $0.processGroupID } ?? sortedProcesses[0]
        let representative = sortedProcesses.last { process in
            !isWrapperCommand(process.command) && !process.state.contains("Z")
        } ?? leader

        let title = shortCommand(representative.command)
        let detail = "\(leader.tty)  pgid \(leader.processGroupID)  \(sortedProcesses.count) proc"

        return TerminalTask(
            id: leader.processGroupID,
            processGroupID: leader.processGroupID,
            tty: leader.tty,
            leaderPID: leader.pid,
            representativePID: representative.pid,
            elapsed: representative.elapsed,
            state: representative.state,
            title: title,
            detail: detail,
            command: representative.command,
            processes: sortedProcesses
        )
    }

    private nonisolated static func isWrapperCommand(_ command: String) -> Bool {
        let lowered = command.lowercased()
        return lowered.hasPrefix("login ")
            || lowered == "-zsh"
            || lowered == "zsh"
            || lowered.hasPrefix("/bin/zsh")
            || lowered.hasPrefix("/bin/bash")
            || lowered.hasPrefix("-bash")
            || lowered.hasPrefix("screen ")
            || lowered.contains("screen -dm")
    }

    nonisolated static func shortCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "terminal" }

        let replacements: [(String, String)] = [
            ("/Users/ben/Desktop/", "~/Desktop/"),
            ("/Users/ben/", "~/")
        ]

        var shortened = trimmed
        replacements.forEach { original, replacement in
            shortened = shortened.replacingOccurrences(of: original, with: replacement)
        }

        if shortened.count > 82 {
            return String(shortened.prefix(79)) + "..."
        }

        return shortened
    }

    private nonisolated static func signalProcessGroup(_ processGroupID: Int32, signal: Int32) {
        guard processGroupID > 1 else { return }
        kill(-processGroupID, signal)
    }

    private nonisolated static func workingDirectory(for pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        return String(data: data, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .first { $0.hasPrefix("n/") }
            .map { String($0.dropFirst()) }
    }
}
