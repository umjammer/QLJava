import AppKit
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    override init() {
        super.init()
        Log.write("PreviewProvider instance initialized!")
    }

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        Log.write("--- QLJava Request Started ---")
        defer { Log.write("--- QLJava Request Finished ---") }

        let runner = ScriptRunner(bundle: Bundle(for: Self.self), scriptName: "ql")
        let output: ScriptRunner.Output
        do {
            output = try runner.run(file: request.fileURL)
        } catch {
            Log.write("Failed to run script: \(error)")
            throw error
        }

        if let png = ScriptRunner.extractPNG(from: output.stdout) {
            let size = NSImage(data: png)?.size ?? CGSize(width: 800, height: 600)
            Log.write("Preview identified as native PNG image (size: \(Int(size.width))x\(Int(size.height)))")
            return QLPreviewReply(dataOfContentType: .png, contentSize: size) { _ in png }
        }

        let html = output.stdout
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 600)) { _ in html }
    }
}
