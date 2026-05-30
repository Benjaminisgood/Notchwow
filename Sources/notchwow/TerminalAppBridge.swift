import Foundation

enum TerminalAppBridge {
    static func openNewWindow(workingDirectory: String) -> Bool {
        let command = "cd -- \(workingDirectory.shellEscaped)"
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return false
            }
            return true
        } catch {
            return false
        }
    }
}
