import AppKit
import Foundation

/// Simple append-only logger to `/tmp/qljava.log` (shared by preview and thumbnail extensions).
enum Log {
    private static let path = "/tmp/qljava.log"
    private static let queue = DispatchQueue(label: "com.vavi.QLJava.log")

    static func write(_ message: @autoclosure () -> String) {
        let line = "\(Date()): \(message())\n"
        queue.sync {
            guard let data = line.data(using: .utf8) else { return }
            let fm = FileManager.default
            if !fm.fileExists(atPath: path) {
                fm.createFile(atPath: path, contents: nil)
            }
            guard let handle = FileHandle(forWritingAtPath: path) else {
                NSLog("QLJava: cannot open log file %@", path)
                return
            }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                NSLog("QLJava: failed to write log file: %@", String(describing: error))
            }
        }
    }
}

enum ScriptError: LocalizedError {
    case scriptNotFound(String)
    case noImage

    var errorDescription: String? {
        switch self {
        case .scriptNotFound(let name): "\(name) script not found in resources bundle."
        case .noImage: "Could not parse image thumbnail output."
        }
    }
}

/// Runs one of the bundled shell scripts (`ql.sh` / `qlt.sh`) against a file.
struct ScriptRunner {
    struct Output {
        let stdout: Data
        let stderr: Data
        let status: Int32
    }

    let bundle: Bundle
    let scriptName: String

    /// The user's real home directory. Inside the sandbox `NSHomeDirectory()` points at the container,
    /// so the scripts receive the real one through `QLJAVA_HOME`.
    static var realHomeDirectory: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    func run(file: URL) throws -> Output {
        guard let scriptPath = bundle.path(forResource: scriptName, ofType: "sh") else {
            Log.write("Error: \(scriptName).sh not found in bundle: \(bundle.resourcePath ?? "-")")
            throw ScriptError.scriptNotFound("\(scriptName).sh")
        }
        let resourcePath = bundle.resourcePath ?? ""
        Log.write("Target file: \(file.path)")
        Log.write("Script path: \(scriptPath)")

        let outPipe = Pipe()
        let errPipe = Pipe()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [scriptPath, file.path, resourcePath]
        var env = ProcessInfo.processInfo.environment
        env["QLJAVA_HOME"] = Self.realHomeDirectory
        task.environment = env
        task.standardOutput = outPipe
        task.standardError = errPipe

        try task.run()

        // Drain both pipes concurrently so the child never blocks on a full pipe buffer.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        }
        DispatchQueue.global().async(group: group) {
            errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
        }
        task.waitUntilExit()
        group.wait()
        try? outPipe.fileHandleForReading.close()
        try? errPipe.fileHandleForReading.close()

        if !errData.isEmpty {
            Log.write("Task stderr:\n\(String(decoding: errData, as: UTF8.self))")
        }
        Log.write("Task exited with status: \(task.terminationStatus), output bytes: \(outData.count)")
        return Output(stdout: outData, stderr: errData, status: task.terminationStatus)
    }

    /// Extracts the first `data:image/png;base64,...` payload embedded in the script output.
    static func extractPNG(from data: Data) -> Data? {
        let text = String(decoding: data, as: UTF8.self)
        let marker = "data:image/png;base64,"
        guard let start = text.range(of: marker),
              let end = text.range(of: "\"", range: start.upperBound..<text.endIndex) else {
            return nil
        }
        let base64 = text[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let png = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), !png.isEmpty else {
            return nil
        }
        return png
    }
}
