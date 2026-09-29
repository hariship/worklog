import AppKit
import SwiftUI
import WorklogCore

/// Plain-text markdown editor with light colouring: headings bold, log times dimmed, #tags tinted,
/// and [[links]] clickable. Typing `[[` offers pages and notes to link. The text stays plain;
/// colour is never saved.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var openLink: (String) -> Void
    /// Link targets completing a partial name typed after `[[`.
    var completions: (String) -> [String] = { _ in [] }

    static let scheme = "worklog-link"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let tv = WikiTextView(frame: .zero)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.drawsBackground = false
        tv.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        tv.string = text
        Self.highlight(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = scroll.documentView as! NSTextView
        guard tv.string != text else { return }
        tv.string = text
        Self.highlight(tv)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            MarkdownEditor.highlight(tv)
            parent.text = tv.string
            // Just typed `[[`: open the completion list. It keeps filtering as you type.
            let cursor = tv.selectedRange().location
            if cursor >= 2, (tv.string as NSString).substring(with: NSRange(location: cursor - 2, length: 2)) == "[[" {
                DispatchQueue.main.async { tv.complete(nil) }
            }
        }

        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange,
                      indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            let before = (textView.string as NSString).substring(to: charRange.location + charRange.length)
            guard let partial = Links.openLinkPrefix(before: before) else { return words }
            return parent.completions(partial).map { $0 + "]]" }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == MarkdownEditor.scheme,
                  let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path, !target.isEmpty
            else { return false }
            parent.openLink(target)
            return true
        }
    }

    /// Completes the whole `[[partial name` (spaces included), not just the last word.
    final class WikiTextView: NSTextView {
        override var rangeForUserCompletion: NSRange {
            let cursor = selectedRange().location
            let before = (string as NSString).substring(to: cursor)
            if let partial = Links.openLinkPrefix(before: before) {
                let length = (partial as NSString).length
                return NSRange(location: cursor - length, length: length)
            }
            return super.rangeForUserCompletion
        }
    }

    // MARK: Colouring

    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let bold = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    private static let timeRegex = try! NSRegularExpression(pattern: #"^- \d{1,2}:\d{2}(-(\d{1,2}:\d{2})?)?( \(\d+h\d{2}\))?"#, options: .anchorsMatchLines)
    private static let tagRegex = try! NSRegularExpression(pattern: #"(?<![\w#])#[A-Za-z0-9][\w-]*"#)
    private static let headingRegex = try! NSRegularExpression(pattern: #"^#{1,6} .*$"#, options: .anchorsMatchLines)

    static func highlight(_ tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let text = tv.string
        let all = NSRange(location: 0, length: (text as NSString).length)
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        storage.beginEditing()
        storage.setAttributes(base, range: all)
        for m in headingRegex.matches(in: text, range: all) {
            storage.addAttribute(.font, value: bold, range: m.range)
        }
        for m in timeRegex.matches(in: text, range: all) {
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: m.range)
        }
        for m in tagRegex.matches(in: text, range: all) {
            storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: m.range)
        }
        for link in Links.matches(in: text) {
            var c = URLComponents()
            c.scheme = scheme
            c.path = link.target // worklog-link:Quilt%20Ops (a host can't hold spaces)
            if let url = c.url { storage.addAttribute(.link, value: url, range: link.range) }
        }
        storage.endEditing()
        // Typed text must never inherit a link or colour from the character before it.
        tv.typingAttributes = base
    }
}
