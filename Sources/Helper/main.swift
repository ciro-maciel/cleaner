import Foundation

/// Cleaner's privileged helper. launchd starts it as root on demand (SMAppService daemon,
/// approved once by the user). It answers only processes signed as Cleaner with the same
/// certificate, and only the actions in CleanerHelperProtocol.

final class Service: NSObject, CleanerHelperProtocol {
    func version(withReply reply: @escaping (String) -> Void) { reply(HelperIdentity.version) }

    func purgeMemory(withReply reply: @escaping (Bool, String) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            reply(p.terminationStatus == 0, out.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            reply(false, error.localizedDescription)
        }
    }
}

final class Delegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: CleanerHelperProtocol.self)
        connection.exportedObject = Service()
        connection.resume()
        return true
    }
}

let delegate = Delegate()
let listener = NSXPCListener(machServiceName: HelperIdentity.label)
// Only Cleaner, signed with the certificate this build was made with.
listener.setConnectionCodeSigningRequirement(HelperRequirement.client)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
