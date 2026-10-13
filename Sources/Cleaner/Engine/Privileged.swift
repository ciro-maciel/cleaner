import Foundation

/// Runs commands, plain or with the administrator password (macOS asks for it).
/// Phase 2 replaces the password path with an SMAppService helper.
enum Privileged {
    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// A shell command with the administrator password, through osascript.
    static func asAdmin(_ command: String, prompt: String) throws {
        // The self-test runs with CLEANER_NO_ADMIN=1: a password prompt there is a failure to
        // report, not a dialog to wait on.
        if ProcessInfo.processInfo.environment["CLEANER_NO_ADMIN"] == "1" { throw Failure(message: "pediu a senha de administrador") }
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let promptEscaped = prompt.replacingOccurrences(of: "\"", with: "'")
        let script = "do shell script \"\(escaped)\" with prompt \"\(promptEscaped)\" with administrator privileges"
        let result = run("/usr/bin/osascript", ["-e", script])
        if result.status != 0 {
            if result.output.contains("-128") { throw Failure(message: "Senha cancelada.") }
            throw Failure(message: result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
