import Foundation

/// JSON 文件持久化：~/Library/Application Support/MiniNotch/
/// 写入失败只打日志不崩溃（todo-data spec）。
enum Persistence {

    static var baseDir: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 截图临时目录（F2 解析用）
    static var screenshotsDir: URL {
        let dir = baseDir.appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = baseDir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            NSLog("[Persistence] decode \(filename) failed: \(error)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to filename: String) {
        let url = baseDir.appendingPathComponent(filename)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("[Persistence] save \(filename) failed: \(error)")
        }
    }
}
