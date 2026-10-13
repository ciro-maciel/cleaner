import Foundation

/// What the privileged helper can do. A closed list on purpose: no command strings, no paths
/// from the caller. Compiled into both the app and the helper.
@objc(CleanerHelperProtocol)
protocol CleanerHelperProtocol {
    /// The helper's version, to tell an outdated one after an update.
    func version(withReply reply: @escaping (String) -> Void)
    /// Runs /usr/sbin/purge (empties the file cache macOS keeps in memory).
    func purgeMemory(withReply reply: @escaping (Bool, String) -> Void)
}

enum HelperIdentity {
    static let label = "click.ciromaciel.cleaner.helper"
    static let plistName = "click.ciromaciel.cleaner.helper.plist"
    static let version = "1"
    static let appID = "click.ciromaciel.cleaner"
}
