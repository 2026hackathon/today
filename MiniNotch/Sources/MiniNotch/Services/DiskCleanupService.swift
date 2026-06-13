import Foundation

// ============================================================
// DiskCleanupService —— 磁盘清理链路（disk-cleanup spec）。
// 借鉴 storage-analyzer skill：只读 du 扫描 → 大模型分安全档 → 移废纸篓。
//
// - 扫描只读，永不在扫描阶段改动文件。
// - 分类交给 AIService（大模型 prompt）；无 Key / 失败时回退规则分类。
// - 清理仅 FileManager.trashItem（移废纸篓，可恢复），逐项确认、永不自动执行。
// ============================================================

// MARK: - 数据类型

/// 清理安全档（与 skill 三档一致）
enum CleanupTier: String, Codable, Sendable, CaseIterable {
    case green   // 纯缓存/临时，可安全清理后自动重建
    case yellow  // 含用户数据 / 需人工判断
    case red     // 可清理但不建议（应用本体 / 系统核心）

    /// 行首彩色圆点（UI 颜色在视图层按档映射）
    var emoji: String {
        switch self {
        case .green: return "🟢"
        case .yellow: return "🟡"
        case .red: return "🔴"
        }
    }

    var label: String {
        switch self {
        case .green: return "可安全清理"
        case .yellow: return "建议确认"
        case .red: return "不建议清理"
        }
    }
}

/// 扫描出的一个空间占用项（目录/文件）
struct DiskEntry: Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    let sizeBytes: Int64

    var id: String { path }

    var sizeHuman: String { ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) }
}

/// 分类后的条目（占用项 + 安全档 + 一句话理由 + 处理建议）
struct ClassifiedEntry: Identifiable, Sendable {
    let entry: DiskEntry
    let tier: CleanupTier
    let rationale: String
    /// 处理建议（黄档对齐 skill：≥3 条；红档给安全处理建议；绿档通常为空）
    let suggestions: [String]

    var id: String { entry.path }
}

/// 磁盘容量（用于展示总量/可用）
struct DiskCapacity: Sendable, Equatable {
    let total: Int64
    let free: Int64

    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var totalHuman: String { ByteCountFormatter.string(fromByteCount: total, countStyle: .file) }
    var freeHuman: String { ByteCountFormatter.string(fromByteCount: free, countStyle: .file) }
    var usedHuman: String { ByteCountFormatter.string(fromByteCount: used, countStyle: .file) }
}

/// 一次扫描结果（容量 + 占用项 + 无法访问的路径）
struct ScanResult: Sendable {
    let capacity: DiskCapacity
    let entries: [DiskEntry]
    let inaccessiblePaths: [String]
}

/// 分类结果（条目 + 是否回退到规则分类）
struct DiskClassification: Sendable {
    let entries: [ClassifiedEntry]
    /// true = 未用大模型（无 Key / AI 失败），已回退规则分类，UI 提示
    let aiUnavailable: Bool
}

// MARK: - AIService 磁盘分类输入/输出（供 AIService 协议复用）

/// 喂给大模型的单项（只给 name/path/size，不读文件内容）
struct StorageItemInput: Sendable {
    let path: String
    let name: String
    let sizeHuman: String
}

/// 大模型返回的单项分类
struct StorageClassification: Sendable {
    let path: String
    let tier: CleanupTier
    let rationale: String
    let suggestions: [String]
}

// MARK: - 服务协议

@MainActor
protocol DiskCleanupService: AnyObject {
    /// 只读扫描磁盘占用 + 容量。永不因单路径无权限而整体失败。
    func scan() async throws -> ScanResult
    /// 分类（大模型优先，失败回退规则）。
    func classify(_ entries: [DiskEntry]) async -> DiskClassification
    /// 移到废纸篓（可恢复）。失败 throw，由上层就地反馈、不中断其余。
    func trash(_ entry: DiskEntry) throws
}

// MARK: - 规则分类（无 Key / AI 失败时兜底，永不失败）

enum StorageRules {
    static func classify(_ entry: DiskEntry) -> (tier: CleanupTier, rationale: String, suggestions: [String]) {
        let p = entry.path.lowercased()
        let green = ["/caches/", "/cache", "deriveddata", "coresimulator", "/.npm",
                     "/.cargo", "/go/pkg", "/.docker", "/tmp/", "node_modules",
                     "/library/caches", "pip", "/uv", "logs"]
        let red = ["/applications/", "/system/", "/library/containers/"]
        if green.contains(where: p.contains) {
            return (.green, "缓存 / 构建产物，清理后可自动重建", [])
        }
        if red.contains(where: p.contains) {
            return (.red, "应用或系统相关，清理可能影响功能", [
                "通过应用自带卸载器或「访达 › 应用程序」正规卸载",
                "系统 / 容器目录不要手删，可能导致应用或系统异常",
                "如需释放空间，优先清理上面的绿色缓存项",
            ])
        }
        if p.contains("/downloads/") {
            return (.yellow, "下载内容，可能仍需要", [
                "先在 Finder 中确认是否还会用到",
                "需要长期保留的移到「文档」等目录归档",
                "确认无用后再移到废纸篓（可恢复）",
            ])
        }
        return (.yellow, "可能含个人数据，需人工判断", [
            "先在 Finder 中查看具体内容再决定",
            "重要文件先备份或移到其它位置",
            "确认是临时产物 / 不再需要后再清理",
        ])
    }
}

// MARK: - 真实现（du 只读扫描 + AIService 分类 + 移废纸篓）

@MainActor
final class RealDiskCleanupService: DiskCleanupService {

    private let ai: AIService

    /// - Parameter ai: 注入的 AI 服务（AppDelegate 用 currentAIService() 装配）。
    ///   无 Key 时它是 MockAIService —— 其分类调用会抛错，触发规则兜底。
    init(ai: AIService) { self.ai = ai }

    func scan() async throws -> ScanResult {
        // du 是阻塞 IO，放到 detached 任务里跑，不卡主线程
        await Task.detached(priority: .userInitiated) {
            DiskScanner.run()
        }.value
    }

    func classify(_ entries: [DiskEntry]) async -> DiskClassification {
        guard !entries.isEmpty else { return DiskClassification(entries: [], aiUnavailable: false) }
        let inputs = entries.map { StorageItemInput(path: $0.path, name: $0.name, sizeHuman: $0.sizeHuman) }
        do {
            let results = try await ai.classifyStorageItems(inputs)
            let byPath = Dictionary(results.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            let classified = entries.map { e -> ClassifiedEntry in
                if let r = byPath[e.path] {
                    return ClassifiedEntry(entry: e, tier: r.tier, rationale: r.rationale, suggestions: r.suggestions)
                }
                // 大模型漏返某项 → 该项走规则兜底
                let f = StorageRules.classify(e)
                return ClassifiedEntry(entry: e, tier: f.tier, rationale: f.rationale, suggestions: f.suggestions)
            }
            return DiskClassification(entries: classified, aiUnavailable: false)
        } catch {
            NSLog("[DiskCleanup] AI classify unavailable, fallback to rules: \(error)")
            let classified = entries.map { e -> ClassifiedEntry in
                let f = StorageRules.classify(e)
                return ClassifiedEntry(entry: e, tier: f.tier, rationale: f.rationale, suggestions: f.suggestions)
            }
            return DiskClassification(entries: classified, aiUnavailable: true)
        }
    }

    func trash(_ entry: DiskEntry) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: entry.path), resultingItemURL: nil)
    }
}

// MARK: - 扫描器（nonisolated：在 detached 任务里跑 du）

enum DiskScanner {

    private static let mb100KB: Int64 = 100 * 1024  // du -sk 单位是 KB
    private static let mb50KB: Int64 = 50 * 1024
    private static let topPerGroup = 40

    static func run() -> ScanResult {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        var entries: [DiskEntry] = []
        var inaccessible: [String] = []
        var seen = Set<String>()

        func append(_ group: [DiskEntry]) {
            for e in group where !seen.contains(e.path) {
                seen.insert(e.path)
                entries.append(e)
            }
        }

        // 「某目录的直接子项」分组：列子项 → du -sk 批量测量 → 过阈值 → 取前 N
        func childrenGroup(of dir: String, thresholdKB: Int64) -> [DiskEntry] {
            let (children, accessible) = immediateChildren(of: dir)
            guard accessible else { inaccessible.append(dir); return [] }
            guard !children.isEmpty else { return [] }
            let sizes = duSizes(children)
            var group: [DiskEntry] = []
            for path in children {
                if let kb = sizes[path] {
                    if kb >= thresholdKB { group.append(makeEntry(path: path, kb: kb)) }
                } else if fm.fileExists(atPath: path) {
                    // 存在但 du 未返回 → 多半无访问权限（未授予完全磁盘访问）
                    inaccessible.append(path)
                }
            }
            return Array(group.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(topPerGroup))
        }

        // Home & /Applications（≥100MB）
        append(childrenGroup(of: home, thresholdKB: mb100KB))
        append(childrenGroup(of: "/Applications", thresholdKB: mb100KB))

        // ~/Library 子区 & ~/Downloads（≥50MB）
        for sub in ["Library/Caches", "Library/Containers", "Library/Application Support"] {
            append(childrenGroup(of: (home as NSString).appendingPathComponent(sub), thresholdKB: mb50KB))
        }
        append(childrenGroup(of: (home as NSString).appendingPathComponent("Downloads"), thresholdKB: mb50KB))

        // 开发者缓存：明确叶子路径，逐个直接测量（≥50MB）
        let devPaths = [
            "Library/Caches/pip", "Library/Caches/uv", ".cargo", ".npm",
            "Library/Developer/Xcode/DerivedData", "Library/Developer/CoreSimulator",
            ".docker", "go/pkg",
        ].map { (home as NSString).appendingPathComponent($0) }
        let existingDev = devPaths.filter { fm.fileExists(atPath: $0) }
        if !existingDev.isEmpty {
            let sizes = duSizes(existingDev)
            var dev: [DiskEntry] = []
            for path in existingDev {
                if let kb = sizes[path], kb >= mb50KB {
                    dev.append(makeEntry(path: path, kb: kb))
                } else if sizes[path] == nil {
                    inaccessible.append(path)
                }
            }
            append(dev.sorted { $0.sizeBytes > $1.sizeBytes })
        }

        entries.sort { $0.sizeBytes > $1.sizeBytes }
        return ScanResult(capacity: capacity(), entries: entries, inaccessiblePaths: inaccessible)
    }

    // MARK: 子进程 / 文件系统辅助

    /// 目录的直接子项绝对路径。第二返回值 false = 目录无访问权限。
    private static func immediateChildren(of dir: String) -> (paths: [String], accessible: Bool) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            return ([], true)  // 不存在 → 不算错误，空结果
        }
        do {
            let names = try fm.contentsOfDirectory(atPath: dir)
            let paths = names
                .filter { !$0.hasPrefix(".") }  // 跳过 dotfile（降噪：.ssh/.Trash 等）
                .map { (dir as NSString).appendingPathComponent($0) }
            return (paths, true)
        } catch {
            return ([], false)  // 权限被拒
        }
    }

    /// `du -sk path...` → [path: KB]。stderr 丢弃（权限告警噪音），单次进程批量测量。
    private static func duSizes(_ paths: [String]) -> [String: Int64] {
        guard !paths.isEmpty else { return [:] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk"] + paths
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [:] }
        // 先读到 EOF（进程结束）再 wait，避免管道缓冲死锁
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: Int64] = [:]
        for line in text.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let kb = Int64(line[..<tab].trimmingCharacters(in: .whitespaces))
            let path = String(line[line.index(after: tab)...])
            if let kb { result[path] = kb }
        }
        return result
    }

    private static func makeEntry(path: String, kb: Int64) -> DiskEntry {
        DiskEntry(path: path, name: (path as NSString).lastPathComponent, sizeBytes: kb * 1024)
    }

    /// 主卷容量（总量 / 可用）
    private static func capacity() -> DiskCapacity {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                     .volumeAvailableCapacityForImportantUsageKey]),
           let total = v.volumeTotalCapacity {
            let free = v.volumeAvailableCapacityForImportantUsage ?? 0
            return DiskCapacity(total: Int64(total), free: Int64(free))
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            let total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            return DiskCapacity(total: total, free: free)
        }
        return DiskCapacity(total: 0, free: 0)
    }
}
