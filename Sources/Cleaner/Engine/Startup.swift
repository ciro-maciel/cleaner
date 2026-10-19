import Foundation

/// launchd jobs that start with the Mac or with the session: LaunchAgents and LaunchDaemons.
struct StartupItem: Identifiable, Hashable {
    enum Domain: String { case user, systemAgent, systemDaemon }

    var id: String { plist }
    let label: String
    let plist: String
    let program: String
    let domain: Domain
    let runAtLoad: Bool
    var disabled: Bool
    var loaded: Bool
    /// Its program has a process right now.
    var running = false

    var vendor: String {
        // com.google.keystone.agent → google
        let parts = label.split(separator: ".")
        return parts.count >= 2 ? String(parts[1]) : label
    }

    var target: String {
        switch domain {
        case .user: return "gui/\(getuid())/\(label)"
        case .systemAgent, .systemDaemon: return "system/\(label)"
        }
    }
}

enum Startup {
    static func list() -> [StartupItem] {
        let home = NSHomeDirectory()
        let folders: [(String, StartupItem.Domain)] = [
            ((home as NSString).appendingPathComponent("Library/LaunchAgents"), .user),
            ("/Library/LaunchAgents", .systemAgent),
            ("/Library/LaunchDaemons", .systemDaemon),
        ]
        let disabledUser = disabledLabels(domain: "gui/\(getuid())")
        let disabledSystem = disabledLabels(domain: "system")
        let loadedUser = loadedLabels()
        let running = Background.runningPaths()

        var items: [StartupItem] = []
        for (folder, domain) in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".plist") {
                let path = (folder as NSString).appendingPathComponent(name)
                guard let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
                      let label = dict["Label"] as? String else { continue }
                let program = (dict["Program"] as? String) ?? ((dict["ProgramArguments"] as? [String])?.first ?? "")
                let disabled = domain == .user ? disabledUser.contains(label) : disabledSystem.contains(label)
                let loaded = domain == .user ? loadedUser.contains(label) : !disabled
                items.append(StartupItem(label: label, plist: path, program: program, domain: domain,
                                         runAtLoad: (dict["RunAtLoad"] as? Bool) ?? false,
                                         disabled: disabled || ((dict["Disabled"] as? Bool) ?? false), loaded: loaded,
                                         running: !program.isEmpty && running.contains(program)))
            }
        }
        return items.sorted { ($0.domain.rawValue, $0.label) < ($1.domain.rawValue, $1.label) }
    }

    /// `launchctl print-disabled` prints lines like `"com.foo.agent" => disabled` (or `=> true`).
    static func disabledLabels(domain: String) -> Set<String> {
        let out = Privileged.run("/bin/launchctl", ["print-disabled", domain]).output
        var set = Set<String>()
        for line in out.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("disabled") || value.hasPrefix("true") else { continue }
            set.insert(parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
        return set
    }

    /// `launchctl list` shows the jobs loaded in the user's session.
    static func loadedLabels() -> Set<String> {
        let out = Privileged.run("/bin/launchctl", ["list"]).output
        return Set(out.split(separator: "\n").dropFirst().compactMap { line in
            line.split(separator: "\t").last.map(String.init)
        })
    }

    /// Turning off is reversible: `disable` survives restarts, `bootout` stops it now.
    /// The plist stays where it is.
    static func setEnabled(_ item: StartupItem, _ enabled: Bool) throws {
        let domain = item.domain == .user ? "gui/\(getuid())" : "system"
        let commands: [[String]] = enabled
            ? [["enable", item.target], ["bootstrap", domain, item.plist]]
            : [["bootout", item.target], ["disable", item.target]]
        if item.domain == .user {
            for args in commands {
                let r = Privileged.run("/bin/launchctl", args)
                // bootout of a job that is not running and bootstrap of one already loaded are fine.
                if r.status != 0 && args[0] != "bootout" && args[0] != "bootstrap" {
                    throw Privileged.Failure(message: r.output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        } else {
            let script = commands.map { "/bin/launchctl " + $0.map(Privileged.quoted).joined(separator: " ") + " || true" }
                .joined(separator: "; ")
            try Privileged.asAdmin(script, prompt: enabled
                ? L("Cleaner needs the administrator password to turn on %@, which is a system startup item.", item.label)
                : L("Cleaner needs the administrator password to turn off %@, which is a system startup item.", item.label))
        }
    }
}
