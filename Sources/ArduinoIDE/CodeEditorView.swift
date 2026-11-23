import AppKit
import SwiftUI

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var requestedLine: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = EditorPalette.background

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textColor = EditorPalette.text
        textView.insertionPointColor = EditorPalette.text
        textView.backgroundColor = EditorPalette.background
        textView.font = EditorPalette.font
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.string = text

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = false
            textContainer.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = LineNumberRulerView(
            textView: textView,
            scrollView: scrollView
        )

        context.coordinator.highlight(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
            context.coordinator.highlight(textView)
            (scrollView.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
        }
        if let line = requestedLine {
            context.coordinator.jump(to: line, in: textView)
            DispatchQueue.main.async {
                requestedLine = nil
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        private var highlightWorkItem: DispatchWorkItem?

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            scheduleHighlight(textView)
            (textView.enclosingScrollView?.verticalRulerView as? LineNumberRulerView)?.needsDisplay = true
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard replacementString == "\t" else { return true }
            textView.insertText("    ", replacementRange: affectedCharRange)
            return false
        }

        func jump(to line: Int, in textView: NSTextView) {
            let source = textView.string as NSString
            var location = 0
            if line > 1 {
                for _ in 1..<line {
                    let remaining = NSRange(location: location, length: max(0, source.length - location))
                    let newline = source.range(of: "\n", options: [], range: remaining)
                    if newline.location == NSNotFound { break }
                    location = newline.location + 1
                }
            }
            location = min(location, source.length)
            textView.setSelectedRange(NSRange(location: location, length: 0))
            textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        }

        private func scheduleHighlight(_ textView: NSTextView) {
            highlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                highlight(textView)
            }
            highlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: workItem)
        }

        func highlight(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else { return }

            textStorage.beginEditing()
            textStorage.addAttribute(.font, value: EditorPalette.font, range: fullRange)
            textStorage.addAttribute(.foregroundColor, value: EditorPalette.text, range: fullRange)

            apply(#"\b(?:void|bool|boolean|byte|char|double|float|int|long|short|unsigned|signed|String|size_t|uint8_t|uint16_t|uint32_t)\b"#, color: EditorPalette.type, to: textStorage)
            apply(#"\b(?:if|else|for|while|do|switch|case|break|continue|return|const|static|volatile|sizeof|typedef|struct|class|public|private|protected|true|false|nullptr|HIGH|LOW|INPUT|OUTPUT|INPUT_PULLUP)\b"#, color: EditorPalette.keyword, to: textStorage)
            apply(#"\b\d+(?:\.\d+)?(?:[uUlLfF]*)\b"#, color: EditorPalette.number, to: textStorage)
            apply(#"^\s*#\s*[A-Za-z_]\w*"#, color: EditorPalette.preprocessor, to: textStorage, options: [.anchorsMatchLines])
            apply(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: EditorPalette.string, to: textStorage)
            apply(#"//[^\n]*|/\*[\s\S]*?\*/"#, color: EditorPalette.comment, to: textStorage)
            textStorage.endEditing()
        }

        private func apply(
            _ pattern: String,
            color: NSColor,
            to textStorage: NSTextStorage,
            options: NSRegularExpression.Options = []
        ) {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let range = NSRange(location: 0, length: textStorage.length)
            for match in expression.matches(in: textStorage.string, range: range) {
                textStorage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
    }
}

private final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        EditorPalette.gutter.setFill()
        bounds.fill()

        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        layoutManager.ensureLayout(for: textContainer)
        let visibleContainerRect = textView.visibleRect.offsetBy(
            dx: -textView.textContainerOrigin.x,
            dy: -textView.textContainerOrigin.y
        )
        let visibleGlyphs = layoutManager.glyphRange(
            forBoundingRect: visibleContainerRect,
            in: textContainer
        )
        let source = textView.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: EditorPalette.font,
            .foregroundColor: EditorPalette.lineNumber
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: visibleGlyphs) {
            lineFragmentRect, _, _, glyphRange, _ in
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            let characterLocation = min(characterRange.location, source.length)
            let lineNumber = source.substring(to: characterLocation).filter { $0 == "\n" }.count + 1
            let label = "\(lineNumber)" as NSString
            let labelSize = label.size(withAttributes: attributes)
            let textViewRect = lineFragmentRect.offsetBy(
                dx: textView.textContainerOrigin.x,
                dy: textView.textContainerOrigin.y
            )
            let rulerRect = textView.convert(textViewRect, to: self)
            label.draw(
                at: NSPoint(
                    x: self.ruleThickness - labelSize.width - 8,
                    y: rulerRect.midY - labelSize.height / 2
                ),
                withAttributes: attributes
            )
        }
    }
}

private enum EditorPalette {
    static let background = NSColor(calibratedRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1)
    static let gutter = NSColor(calibratedRed: 0x25 / 255, green: 0x25 / 255, blue: 0x26 / 255, alpha: 1)
    static let text = NSColor(calibratedWhite: 0.83, alpha: 1)
    static let lineNumber = NSColor(calibratedWhite: 0.48, alpha: 1)
    static let keyword = NSColor(calibratedRed: 0.34, green: 0.61, blue: 0.84, alpha: 1)
    static let type = NSColor(calibratedRed: 0.31, green: 0.78, blue: 0.69, alpha: 1)
    static let number = NSColor(calibratedRed: 0.71, green: 0.56, blue: 0.85, alpha: 1)
    static let preprocessor = NSColor(calibratedRed: 0.78, green: 0.57, blue: 0.35, alpha: 1)
    static let string = NSColor(calibratedRed: 0.81, green: 0.57, blue: 0.47, alpha: 1)
    static let comment = NSColor(calibratedRed: 0.43, green: 0.63, blue: 0.38, alpha: 1)
    static let font = NSFont(name: "Menlo", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
}
