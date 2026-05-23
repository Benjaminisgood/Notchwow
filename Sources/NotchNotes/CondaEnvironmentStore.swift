import Combine
import Foundation

struct CondaEnvironment: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let path: String
    let isActive: Bool
    let isFrozen: Bool

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    var displayName: String {
        var labels = [name]
        if isActive {
            labels.append("active")
        }
        if isFrozen {
            labels.append("frozen")
        }
        return labels.joined(separator: " ")
    }
}

struct PythonRunCommand {
    let command: String
    let displayCommand: String
    let displayPrompt: String
}

@MainActor
final class CondaEnvironmentStore: ObservableObject {
    @Published private(set) var environments: [CondaEnvironment] = []
    @Published private(set) var selectedEnvironmentName: String
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private static let selectedEnvironmentKey = "notchNotes.selectedCondaEnvironment"
    private let condaBin: String

    init() {
        condaBin = Self.resolveCondaExecutable()
        selectedEnvironmentName = UserDefaults.standard.string(forKey: Self.selectedEnvironmentKey) ?? "base"
        refresh()
    }

    var selectedEnvironment: CondaEnvironment? {
        environments.first { $0.name == selectedEnvironmentName }
    }

    var condaExecutablePath: String {
        condaBin
    }

    func select(_ name: String) {
        selectedEnvironmentName = name
        UserDefaults.standard.set(name, forKey: Self.selectedEnvironmentKey)
    }

    func refresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        lastError = nil
        let condaBin = condaBin
        let currentSelection = selectedEnvironmentName

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.loadEnvironments(condaBin: condaBin)

            Task { @MainActor in
                self.isRefreshing = false

                switch result {
                case .success(let loadedEnvironments):
                    self.environments = loadedEnvironments

                    if loadedEnvironments.contains(where: { $0.name == currentSelection }) {
                        self.select(currentSelection)
                    } else if let activeEnvironment = loadedEnvironments.first(where: \.isActive) {
                        self.select(activeEnvironment.name)
                    } else if let firstEnvironment = loadedEnvironments.first {
                        self.select(firstEnvironment.name)
                    }

                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func condaCommand(_ arguments: String) -> String {
        "\(condaBin.shellEscaped) \(arguments)"
    }

    func commandInSelectedEnvironment(_ command: String) -> String {
        shellCommandInSelectedEnvironment(command)
    }

    func runPythonFileCommand(filePath: String) -> String {
        if let pythonExecutablePath {
            return "\(pythonExecutablePath.shellEscaped) \(filePath.shellEscaped)"
        }

        return "\(condaBin.shellEscaped) run -n \(selectedEnvironmentName.shellEscaped) python \(filePath.shellEscaped)"
    }

    func runPythonFileDisplayCommand(filePath: String) -> String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    func pythonConsoleCommand(_ rawCommand: String) -> PythonRunCommand? {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }

        if let shellCommand = Self.shellCommand(from: command) {
            return PythonRunCommand(
                command: shellCommandInSelectedEnvironment(shellCommand),
                displayCommand: shortDisplay(shellCommand),
                displayPrompt: "py!"
            )
        }

        return PythonRunCommand(
            command: pythonSnippetCommand(command),
            displayCommand: shortDisplay(command),
            displayPrompt: "py>"
        )
    }

    private var selectedEnvironmentPath: String? {
        if let selectedEnvironment {
            return selectedEnvironment.path
        }

        if selectedEnvironmentName == "base" {
            return WorkspacePaths.condaRoot.path
        }

        let inferredPath = WorkspacePaths.condaRoot
            .appendingPathComponent("envs", isDirectory: true)
            .appendingPathComponent(selectedEnvironmentName, isDirectory: true)
            .path
        guard FileManager.default.fileExists(atPath: inferredPath) else { return nil }
        return inferredPath
    }

    private var pythonExecutablePath: String? {
        guard let selectedEnvironmentPath else { return nil }
        let path = URL(fileURLWithPath: selectedEnvironmentPath, isDirectory: true)
            .appendingPathComponent("bin/python", isDirectory: false)
            .path
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    private func shellCommandInSelectedEnvironment(_ command: String) -> String {
        if let selectedEnvironmentPath {
            let binPath = URL(fileURLWithPath: selectedEnvironmentPath, isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .path
            return "PATH=\(binPath.shellEscaped):$PATH CONDA_PREFIX=\(selectedEnvironmentPath.shellEscaped) /bin/zsh -lc \(command.shellEscaped)"
        }

        return "\(condaBin.shellEscaped) run -n \(selectedEnvironmentName.shellEscaped) /bin/zsh -lc \(command.shellEscaped)"
    }

    private func pythonSnippetCommand(_ code: String) -> String {
        let wrapper = Self.pythonSnippetWrapper(for: code)
        if let pythonExecutablePath {
            return "\(pythonExecutablePath.shellEscaped) -c \(wrapper.shellEscaped)"
        }

        return "\(condaBin.shellEscaped) run -n \(selectedEnvironmentName.shellEscaped) python -c \(wrapper.shellEscaped)"
    }

    private func shortDisplay(_ command: String) -> String {
        let singleLine = command
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard singleLine.count > 96 else { return singleLine }
        return String(singleLine.prefix(93)) + "..."
    }

    private nonisolated static func resolveCondaExecutable() -> String {
        let preferredPath = WorkspacePaths.condaExecutable.path
        if FileManager.default.isExecutableFile(atPath: preferredPath) {
            return preferredPath
        }

        return "conda"
    }

    private nonisolated static func shellCommand(from command: String) -> String? {
        if command.hasPrefix("!") {
            let shellCommand = String(command.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return shellCommand.isEmpty ? nil : shellCommand
        }

        let shellPrefixes = [
            "./", "/", "cd ", "ls", "pwd", "which ", "where ", "pip ", "python ",
            "conda ", "mamba ", "uv ", "pytest", "git ", "cat ", "echo ",
            "mkdir ", "rm ", "cp ", "mv ", "open ", "brew ", "curl ", "wget "
        ]

        return shellPrefixes.contains { prefix in
            let commandName = prefix.trimmingCharacters(in: .whitespaces)
            return command == commandName || command.hasPrefix(prefix)
        }
            ? command
            : nil
    }

    private nonisolated static func pythonSnippetWrapper(for code: String) -> String {
        let encodedCode = Data(code.utf8).base64EncodedString()
        return """
        import ast
        import base64

        _code = base64.b64decode("\(encodedCode)").decode("utf-8")
        _parsed = ast.parse(_code, mode="exec")
        if _parsed.body and isinstance(_parsed.body[-1], ast.Expr):
            _prefix = ast.Module(body=_parsed.body[:-1], type_ignores=[])
            ast.fix_missing_locations(_prefix)
            exec(compile(_prefix, "<notchwow>", "exec"), globals(), globals())

            _expression = ast.Expression(_parsed.body[-1].value)
            ast.fix_missing_locations(_expression)
            _result = eval(compile(_expression, "<notchwow>", "eval"), globals(), globals())
            if _result is not None:
                print(repr(_result))
        else:
            exec(compile(_parsed, "<notchwow>", "exec"), globals(), globals())
        """
    }

    private nonisolated static func loadEnvironments(condaBin: String) -> Result<[CondaEnvironment], Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "\(condaBin.shellEscaped) info --envs"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw CondaEnvironmentError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            return .success(parseEnvironments(from: output))
        } catch {
            return .failure(error)
        }
    }

    private nonisolated static func parseEnvironments(from output: String) -> [CondaEnvironment] {
        output
            .components(separatedBy: .newlines)
            .compactMap(parseEnvironmentLine)
    }

    private nonisolated static func parseEnvironmentLine(_ line: String) -> CondaEnvironment? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        let parts = trimmed
            .split { $0 == " " || $0 == "\t" }
            .map(String.init)

        guard let path = parts.last, path.hasPrefix("/") else { return nil }
        let statusMarkers = Set(["*", "+"])
        let name = parts.first { !statusMarkers.contains($0) }
            ?? URL(fileURLWithPath: path).lastPathComponent

        return CondaEnvironment(
            name: name,
            path: path,
            isActive: parts.contains("*"),
            isFrozen: parts.contains("+")
        )
    }
}

enum CondaEnvironmentError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return output.isEmpty ? "conda info --envs failed" : output
        }
    }
}
