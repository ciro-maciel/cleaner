import Foundation
import Darwin

/// Disk usage measured with fts(3): allocated blocks, physical walk, one volume.
enum DiskUsage {
    struct Volume {
        let total: Int64
        let available: Int64
        var used: Int64 { total - available }
    }

    static func volume(for path: String = NSHomeDirectory()) -> Volume? {
        let url = URL(fileURLWithPath: path)
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity else { return nil }
        let available = v.volumeAvailableCapacityForImportantUsage ?? 0
        return Volume(total: Int64(total), available: available)
    }

    /// Allocated size of a file or a whole folder.
    static func size(of path: String) -> Int64 {
        var result: Int64 = 0
        walk(path, record: nil) { result = $0 }
        return result
    }

    /// Walks `root`, calling `done` with its total size. When `record` is given, every folder
    /// under it gets its own total, so a disk map can drill down without walking again.
    /// Returns how many entries could not be read (permission).
    @discardableResult
    static func walk(_ root: String, record: ((String, Int64) -> Void)?, progress: (() -> Void)? = nil, cancelled: (() -> Bool)? = nil, done: (Int64) -> Void) -> Int {
        var denied = 0
        guard let cRoot = strdup(root) else { done(0); return 0 }
        defer { free(cRoot) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cRoot, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { done(0); return 0 }
        defer { fts_close(fts) }

        var total: Int64 = 0
        var tick = 0
        while let entry = fts_read(fts) {
            let e = entry.pointee
            let blocks = e.fts_statp.map { Int64($0.pointee.st_blocks) * 512 } ?? 0
            switch Int32(e.fts_info) {
            case FTS_D:
                entry.pointee.fts_number = 0
                if let cancelled, tick % 512 == 0, cancelled() { done(total); return denied }
            case FTS_DP:
                let size = Int64(e.fts_number) + blocks
                if let record { record(String(cString: e.fts_path), size) }
                if e.fts_level == 0 { total = size } else { e.fts_parent.pointee.fts_number += Int(size) }
            case FTS_DNR:
                denied += 1
                if e.fts_level == 0 { total = blocks } else { e.fts_parent.pointee.fts_number += Int(blocks) }
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                if e.fts_level == 0 { total = blocks } else { e.fts_parent.pointee.fts_number += Int(blocks) }
                tick += 1
                if let progress, tick % 256 == 0 { progress() }
            case FTS_ERR, FTS_NS:
                denied += 1
            default:
                break
            }
        }
        done(total)
        return denied
    }
}

/// A folder tree measured once, in parallel by top-level child, then browsed from memory.
final class DiskIndex: @unchecked Sendable {
    let root: String
    private(set) var sizes: [String: Int64] = [:]
    private(set) var denied = 0
    private let lock = NSLock()
    private var filesSeen = 0

    init(root: String) { self.root = root }

    var scannedFiles: Int { lock.lock(); defer { lock.unlock() }; return filesSeen }

    func size(of path: String) -> Int64? { lock.lock(); defer { lock.unlock() }; return sizes[path] }

    func build(cancelled: @escaping @Sendable () -> Bool) async {
        let children = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        let paths = children.map { (root as NSString).appendingPathComponent($0) }
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            let width = max(ProcessInfo.processInfo.activeProcessorCount, 4)
            for path in paths {
                if running >= width { await group.next(); running -= 1 }
                running += 1
                group.addTask { [self] in self.measure(path, cancelled: cancelled) }
            }
        }
        let rootTotal = paths.reduce(Int64(0)) { $0 + (size(of: $1) ?? 0) }
        lock.withLock { sizes[root] = rootTotal }
    }

    /// Something left `path` (moved to the quarantine): forget it and everything under it, and
    /// take its size off every folder above it. No walk: the tree stays as measured.
    func removed(_ path: String, size: Int64) {
        lock.withLock {
            let prefix = path.hasSuffix("/") ? path : path + "/"
            for key in sizes.keys where key == path || key.hasPrefix(prefix) { sizes[key] = nil }
            adjustAncestors(of: path, by: -size)
        }
    }

    /// Something arrived at `path` (the quarantine copy, when it sits inside this tree).
    func added(_ path: String, size: Int64) {
        lock.withLock {
            guard path.hasPrefix(root + "/") else { return }
            if sizes[path] == nil { sizes[path] = size }
            adjustAncestors(of: path, by: size)
        }
    }

    /// Caller holds the lock.
    private func adjustAncestors(of path: String, by delta: Int64) {
        var parent = (path as NSString).deletingLastPathComponent
        while parent.count >= root.count {
            if let v = sizes[parent] { sizes[parent] = max(0, v + delta) }
            else if delta > 0 { sizes[parent] = delta }
            if parent == root { break }
            parent = (parent as NSString).deletingLastPathComponent
        }
    }

    private func measure(_ path: String, cancelled: @escaping () -> Bool) {
        var local: [String: Int64] = [:]
        let denied = DiskUsage.walk(path, record: { local[$0] = $1 }, progress: { [self] in
            lock.lock(); filesSeen += 256; lock.unlock()
        }, cancelled: cancelled) { total in
            local[path] = total
        }
        lock.lock()
        sizes.merge(local) { a, _ in a }
        self.denied += denied
        filesSeen += 1
        lock.unlock()
    }
}
