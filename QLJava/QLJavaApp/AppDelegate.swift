import Cocoa

/// Host application for the QLJava Quick Look extensions.
///
/// Quick Look app extensions are only discovered when they are embedded in an application that
/// LaunchServices knows about. Launching this app (re)registers the embedded extensions with
/// `pluginkit`, enables them, and resets the Quick Look caches, then shows their status.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        registerExtensions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - UI

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "QLJava Quick Look Extensions"
        window.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: "QLJava Quick Look Extensions")
        title.font = .boldSystemFont(ofSize: 15)

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.isSelectable = true

        let hint = NSTextField(wrappingLabelWithString:
            "If previews do not appear, enable the extensions in System Settings → General → "
            + "Login Items & Extensions → Quick Look.")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor

        let reRegister = NSButton(title: "Register Again", target: self, action: #selector(reRegisterClicked))
        let settings = NSButton(title: "Open Extension Settings…", target: self, action: #selector(openSettingsClicked))
        let buttons = NSStackView(views: [reRegister, settings])
        buttons.orientation = .horizontal

        let stack = NSStackView(views: [title, statusLabel, hint, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: 480),
            hint.widthAnchor.constraint(equalToConstant: 480),
        ])
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func reRegisterClicked(_ sender: Any?) { registerExtensions() }

    @objc private func openSettingsClicked(_ sender: Any?) {
        let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Registration

    private var embeddedExtensions: [(path: String, id: String)] {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let items = try? FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)
        else { return [] }
        return items.filter { $0.pathExtension == "appex" }.compactMap { url in
            guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
            return (url.path, id)
        }
    }

    private func registerExtensions() {
        statusLabel.stringValue = "Registering…"
        let extensions = embeddedExtensions
        DispatchQueue.global(qos: .userInitiated).async {
            for ext in extensions {
                Self.run("/usr/bin/pluginkit", ["-a", ext.path])
                Self.run("/usr/bin/pluginkit", ["-e", "use", "-i", ext.id])
            }
            Self.run("/usr/bin/qlmanage", ["-r"])
            Self.run("/usr/bin/qlmanage", ["-r", "cache"])

            let status = extensions.map { ext -> String in
                let out = Self.run("/usr/bin/pluginkit", ["-m", "-i", ext.id])
                let state: String
                switch out.trimmingCharacters(in: .whitespacesAndNewlines).first {
                case "+": state = "enabled"
                case "-": state = "disabled"
                case nil: state = "not registered"
                default: state = "registered"
                }
                return "\(ext.id): \(state)"
            }.joined(separator: "\n")

            DispatchQueue.main.async {
                self.statusLabel.stringValue = status.isEmpty ? "No embedded extensions found." : status
            }
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return ""
        }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
