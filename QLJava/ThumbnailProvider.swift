import AppKit
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {

    override init() {
        super.init()
        Log.write("ThumbnailProvider instance initialized!")
    }

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        Log.write("--- QLJava Thumbnail Request Started ---")

        let runner = ScriptRunner(bundle: Bundle(for: Self.self), scriptName: "qlt")
        let output: ScriptRunner.Output
        do {
            output = try runner.run(file: request.fileURL)
        } catch {
            Log.write("Thumbnail failed to run script: \(error)")
            handler(nil, error)
            return
        }

        guard let png = ScriptRunner.extractPNG(from: output.stdout), let image = NSImage(data: png) else {
            Log.write("--- QLJava Thumbnail Request Finished With Error ---")
            handler(nil, ScriptError.noImage)
            return
        }

        // Aspect-fit the image into the size Quick Look asked for.
        let maxSize = request.maximumSize
        var size = image.size
        if size.width <= 0 || size.height <= 0 {
            size = maxSize
        } else {
            let scale = min(maxSize.width / size.width, maxSize.height / size.height, 1)
            size = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        }
        Log.write("Thumbnail generated image size: \(Int(size.width))x\(Int(size.height))")
        let reply = QLThumbnailReply(contextSize: size) {
            image.draw(in: NSRect(origin: .zero, size: size))
            return true
        }
        handler(reply, nil)
        Log.write("--- QLJava Thumbnail Request Finished Successfully ---")
    }
}
