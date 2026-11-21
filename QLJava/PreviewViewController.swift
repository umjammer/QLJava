import AppKit
import QuickLookUI
import UniformTypeIdentifiers

/// View-based Quick Look preview.
///
/// Finder's preview pane (column view / ⇧⌘P) only shows native views; a data-based HTML reply is
/// ignored there. So the script output is rendered natively:
/// - archive listing (JSON from `vavi_util_archive ... json`) → outline view like the built-in zip preview
/// - embedded `data:image/png;base64,...` → image view
/// - anything else (HTML) → text view
final class PreviewViewController: NSViewController, QLPreviewingController {

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        preferredContentSize = NSSize(width: 800, height: 600)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        Log.write("--- QLJava Request Started ---")
        defer { Log.write("--- QLJava Request Finished ---") }

        let runner = ScriptRunner(bundle: Bundle(for: Self.self), scriptName: "ql")
        let output = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ScriptRunner.Output, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(with: Result { try runner.run(file: url) })
            }
        }

        let content: NSView
        if let listing = ArchiveListing.parse(output.stdout) {
            Log.write("Preview as archive listing (\(listing.entries.count) entries)")
            content = ArchiveOutlineView(listing: listing)
        } else if let png = ScriptRunner.extractPNG(from: output.stdout), let image = NSImage(data: png) {
            Log.write("Preview as image (size: \(Int(image.size.width))x\(Int(image.size.height)))")
            let imageView = NSImageView(image: image)
            imageView.imageScaling = .scaleProportionallyDown
            imageView.imageAlignment = .alignCenter
            preferredContentSize = image.size
            content = imageView
        } else if !output.stdout.isEmpty {
            Log.write("Preview as html text")
            content = Self.textView(html: output.stdout)
        } else {
            throw ScriptError.noPreview
        }
        install(content)
    }

    private func install(_ content: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private static func textView(html: Data) -> NSView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let attributed = try? NSAttributedString(data: html, options: options, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        } else {
            textView.string = String(decoding: html, as: UTF8.self)
        }
        return scroll
    }
}

// MARK: - archive model

/// JSON produced by `vavi.util.archive.ArchivesMain --json`.
struct ArchiveListing: Decodable {
    struct Entry: Decodable {
        let name: String
        let directory: Bool
        let size: Int64
        let compressedSize: Int64
        let time: Int64
    }

    let name: String
    let entries: [Entry]

    /// Cuts the JSON object out of the script output (java logging may be mixed into it) and decodes it.
    static func parse(_ data: Data) -> ArchiveListing? {
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.range(of: "{\"name\":"),
              let end = text.range(of: "]}", options: .backwards),
              start.lowerBound < end.upperBound else { return nil }
        let json = Data(text[start.lowerBound..<end.upperBound].utf8)
        do {
            return try JSONDecoder().decode(ArchiveListing.self, from: json)
        } catch {
            Log.write("Archive json decode failed: \(error)")
            return nil
        }
    }
}

/// A node of the archive's directory tree.
final class ArchiveNode {
    let name: String
    var isDirectory: Bool
    var size: Int64 = 0
    var date: Date?
    var children: [ArchiveNode] = []
    private var index: [String: ArchiveNode] = [:]

    init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }

    /// Builds the tree from flat entry paths (`/` or `\` separated); missing parent directories are created.
    static func tree(from entries: [ArchiveListing.Entry]) -> ArchiveNode {
        let root = ArchiveNode(name: "", isDirectory: true)
        for entry in entries {
            let parts = entry.name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
            guard !parts.isEmpty else { continue }
            var node = root
            for (i, part) in parts.enumerated() {
                let isLast = i == parts.count - 1
                node = node.child(named: part, isDirectory: !isLast || entry.directory)
            }
            if !entry.directory {
                node.isDirectory = false
                node.size = entry.size
            }
            if entry.time > 0 {
                node.date = Date(timeIntervalSince1970: TimeInterval(entry.time) / 1000)
            }
        }
        return root
    }

    private func child(named name: String, isDirectory: Bool) -> ArchiveNode {
        if let existing = index[name] { return existing }
        let node = ArchiveNode(name: name, isDirectory: isDirectory)
        index[name] = node
        children.append(node)
        return node
    }

    var count: Int { children.reduce(children.count) { $0 + $1.count } }
    var totalSize: Int64 { children.reduce(size) { $0 + $1.totalSize } }
}

// MARK: - archive view

/// "N items, uncompressed size: X" header + outline view, modeled on the built-in zip preview.
final class ArchiveOutlineView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {

    private let root: ArchiveNode
    private let outline = NSOutlineView()
    private let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private enum Column: String, CaseIterable {
        case name, size, date

        var title: String {
            switch self {
            case .name: "Name"
            case .size: "Size"
            case .date: "Date Modified"
            }
        }
    }

    init(listing: ArchiveListing) {
        root = ArchiveNode.tree(from: listing.entries)
        super.init(frame: .zero)

        let count = root.count
        let header = NSTextField(labelWithString:
            "\(count) item\(count == 1 ? "" : "s"), uncompressed size: \(sizeFormatter.string(fromByteCount: root.totalSize))")
        header.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        header.textColor = .secondaryLabelColor
        header.lineBreakMode = .byTruncatingTail

        for column in Column.allCases {
            let tc = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tc.title = column.title
            switch column {
            case .name: tc.width = 320; tc.minWidth = 120
            case .size: tc.width = 80; tc.minWidth = 50
            case .date: tc.width = 160; tc.minWidth = 80
            }
            outline.addTableColumn(tc)
            if column == .name { outline.outlineTableColumn = tc }
        }
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.usesAlternatingRowBackgroundColors = true
        outline.style = .fullWidth
        outline.rowSizeStyle = .default
        outline.allowsMultipleSelection = true
        outline.autosaveExpandedItems = false
        outline.dataSource = self
        outline.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let stack = NSStackView(views: [header, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor, constant: -12),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? ArchiveNode) ?? root).children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? ArchiveNode) ?? root).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? ArchiveNode)?.children.isEmpty ?? true)
    }

    // MARK: delegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? ArchiveNode,
              let id = tableColumn?.identifier, let column = Column(rawValue: id.rawValue) else { return nil }

        let cell = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? makeCell(id: id, withImage: column == .name)
        switch column {
        case .name:
            cell.textField?.stringValue = node.name
            cell.imageView?.image = Self.icon(for: node)
        case .size:
            cell.textField?.stringValue = node.isDirectory ? "--" : sizeFormatter.string(fromByteCount: node.size)
        case .date:
            cell.textField?.stringValue = node.date.map(dateFormatter.string(from:)) ?? "--"
        }
        return cell
    }

    private func makeCell(id: NSUserInterfaceItemIdentifier, withImage: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        var constraints = [
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
        ]
        if withImage {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            constraints += [
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            ]
        } else {
            constraints.append(text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
        }
        NSLayoutConstraint.activate(constraints)
        return cell
    }

    private static var iconCache: [String: NSImage] = [:]

    private static func icon(for node: ArchiveNode) -> NSImage {
        let key = node.isDirectory ? "/" : (node.name as NSString).pathExtension.lowercased()
        if let cached = iconCache[key] { return cached }
        let type: UTType = node.isDirectory ? .folder : (UTType(filenameExtension: key) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        image.size = NSSize(width: 16, height: 16)
        iconCache[key] = image
        return image
    }
}
