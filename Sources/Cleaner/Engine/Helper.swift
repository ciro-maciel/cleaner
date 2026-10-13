import Foundation
import ServiceManagement

/// The privileged helper, from the app's side: register it once (the user approves it in
/// System Settings → Login Items), then call it over XPC with no password.
enum Helper {
    enum State: Equatable {
        case ready
        case needsApproval        // registered, waiting for the user in System Settings
        case notRegistered
        case unavailable(String)  // macOS refused it
    }

    private static var service: SMAppService { SMAppService.daemon(plistName: HelperIdentity.plistName) }

    static var state: State {
        switch service.status {
        case .enabled: return .ready
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .notRegistered
        @unknown default: return .notRegistered
        }
    }

    /// Registers the helper. The first time macOS answers "requires approval" and lists Cleaner
    /// in Login Items; the user turns it on once.
    @discardableResult
    static func register() -> State {
        do {
            try service.register()
        } catch {
            let ns = error as NSError
            // Already registered is fine; anything else is a real refusal.
            if ns.code != kSMErrorAlreadyRegistered { return state == .notRegistered ? .unavailable(ns.localizedDescription) : state }
        }
        return state
    }

    static func openApproval() { SMAppService.openSystemSettingsLoginItems() }

    // MARK: calls

    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func connection() -> NSXPCConnection {
        let c = NSXPCConnection(machServiceName: HelperIdentity.label, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: CleanerHelperProtocol.self)
        // Talk only to our own helper, signed with the same certificate.
        c.setCodeSigningRequirement(HelperRequirement.helper)
        c.resume()
        return c
    }

    private static func call<T>(_ body: @escaping (CleanerHelperProtocol, @escaping (Result<T, Error>) -> Void) -> Void) async throws -> T {
        let c = connection()
        defer { c.invalidate() }
        return try await withCheckedThrowingContinuation { cont in
            let once = OnceBox()
            let proxy = c.remoteObjectProxyWithErrorHandler { error in
                if once.take() { cont.resume(throwing: Failure(message: "O ajudante não respondeu: \(error.localizedDescription)")) }
            }
            guard let helper = proxy as? CleanerHelperProtocol else {
                if once.take() { cont.resume(throwing: Failure(message: "Ajudante indisponível.")) }
                return
            }
            body(helper) { result in if once.take() { cont.resume(with: result) } }
        }
    }

    static func version() async throws -> String {
        try await call { helper, done in helper.version { done(.success($0)) } }
    }

    static func purgeMemory() async throws {
        try await call { helper, done in
            helper.purgeMemory { ok, message in
                done(ok ? .success(()) : .failure(Failure(message: message.isEmpty ? "O purge falhou." : message)))
            }
        } as Void
    }
}

/// Resumes a continuation once even if XPC reports both an error and a reply.
private final class OnceBox: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func take() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}
