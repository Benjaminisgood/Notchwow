//
//  MathMLToLatexConverter.swift
//  MarkdownEngineLatex
//
//  Converts common Presentation MathML into the LaTeX subset SwiftMath renders.
//

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum MathMLToLatexConverter {
    static func convert(_ source: String) -> String? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^<math\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let data = trimmed.data(using: .utf8) else {
            return nil
        }

        let delegate = MathMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate

        guard parser.parse(),
              let root = delegate.root,
              root.name == "math" else {
            return nil
        }

        let latex = render(root)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return latex.isEmpty ? nil : latex
    }

    private static func render(_ node: MathMLNode) -> String {
        switch node.name {
        case "math", "mrow", "mstyle", "mpadded", "mphantom":
            return renderChildren(node.children)
        case "semantics":
            if let tex = texAnnotation(in: node) {
                return tex
            }
            return renderChildren(node.children.filter { $0.name != "annotation" && $0.name != "annotation-xml" })
        case "annotation", "annotation-xml":
            return ""
        case "mi":
            return identifierLatex(node.plainText)
        case "mn":
            return numberLatex(node.plainText)
        case "mo":
            return operatorLatex(node.plainText)
        case "mtext", "ms":
            return "\\text{\(escapeText(node.plainText))}"
        case "mspace":
            return "\\ "
        case "mfrac":
            guard node.children.count >= 2 else { return renderChildren(node.children) }
            return "\\frac{\(render(node.children[0]))}{\(render(node.children[1]))}"
        case "msqrt":
            return "\\sqrt{\(renderChildren(node.children))}"
        case "mroot":
            guard node.children.count >= 2 else { return renderChildren(node.children) }
            return "\\sqrt[\(render(node.children[1]))]{\(render(node.children[0]))}"
        case "msup":
            guard node.children.count >= 2 else { return renderChildren(node.children) }
            return "{\(render(node.children[0]))}^{\(render(node.children[1]))}"
        case "msub":
            guard node.children.count >= 2 else { return renderChildren(node.children) }
            return "{\(render(node.children[0]))}_{\(render(node.children[1]))}"
        case "msubsup":
            guard node.children.count >= 3 else { return renderChildren(node.children) }
            return "{\(render(node.children[0]))}_{\(render(node.children[1]))}^{\(render(node.children[2]))}"
        case "mover":
            return renderMover(node)
        case "munder":
            guard node.children.count >= 2 else { return renderChildren(node.children) }
            return "{\(render(node.children[0]))}_{\(render(node.children[1]))}"
        case "munderover":
            guard node.children.count >= 3 else { return renderChildren(node.children) }
            return "{\(render(node.children[0]))}_{\(render(node.children[1]))}^{\(render(node.children[2]))}"
        case "mfenced":
            return renderFenced(node)
        case "mtable":
            return renderTable(node)
        case "mtr", "mlabeledtr":
            return node.children.filter { $0.name == "mtd" }.map(render).joined(separator: " & ")
        case "mtd":
            return renderChildren(node.children)
        default:
            if node.children.isEmpty {
                return identifierLatex(node.plainText)
            }
            return renderChildren(node.children)
        }
    }

    private static func renderChildren(_ children: [MathMLNode]) -> String {
        children.map(render).joined()
    }

    private static func texAnnotation(in node: MathMLNode) -> String? {
        for child in node.children where child.name == "annotation" {
            let encoding = child.attributes["encoding", default: ""].lowercased()
            if encoding.contains("tex") || encoding.contains("latex") {
                let text = child.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private static func renderMover(_ node: MathMLNode) -> String {
        guard node.children.count >= 2 else { return renderChildren(node.children) }
        let base = render(node.children[0])
        let accentText = node.children[1].plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch accentText {
        case "^":
            return "\\hat{\(base)}"
        case "\u{00AF}", "\u{203E}":
            return "\\overline{\(base)}"
        case "\u{2192}":
            return "\\vec{\(base)}"
        case ".":
            return "\\dot{\(base)}"
        default:
            return "{\(base)}^{\(render(node.children[1]))}"
        }
    }

    private static func renderFenced(_ node: MathMLNode) -> String {
        let open = delimiterLatex(node.attributes["open"] ?? "(")
        let close = delimiterLatex(node.attributes["close"] ?? ")")
        let separator = node.attributes["separators"].flatMap { $0.first.map(String.init) } ?? ","
        let body = node.children.map(render).joined(separator: operatorLatex(separator))
        return "\\left\(open) \(body) \\right\(close)"
    }

    private static func renderTable(_ node: MathMLNode) -> String {
        let rows = node.children
            .filter { $0.name == "mtr" || $0.name == "mlabeledtr" }
            .map(render)
        guard !rows.isEmpty else { return renderChildren(node.children) }
        return "\\begin{matrix} \(rows.joined(separator: #" \\ "#)) \\end{matrix}"
    }

    private static func identifierLatex(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let command = symbolCommands[trimmed] {
            return commandWithTrailingSpace(command)
        }
        if knownOperators.contains(trimmed) {
            return "\\\(trimmed) "
        }
        if trimmed.range(of: #"^[A-Za-z]$"#, options: .regularExpression) != nil {
            return trimmed
        }
        if trimmed.range(of: #"^[A-Za-z]+$"#, options: .regularExpression) != nil {
            return "\\mathrm{\(escapeText(trimmed))}"
        }
        return latexForCharacters(trimmed)
    }

    private static func numberLatex(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func operatorLatex(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let command = operatorCommands[trimmed] ?? symbolCommands[trimmed] {
            return " \(commandWithTrailingSpace(command))"
        }
        return trimmed
    }

    private static func delimiterLatex(_ text: String) -> String {
        switch text {
        case "{": return "\\{"
        case "}": return "\\}"
        case "\u{2223}": return "|"
        case "\u{2225}": return "\\|"
        default: return operatorCommands[text] ?? text
        }
    }

    private static func latexForCharacters(_ text: String) -> String {
        text.map { character -> String in
            let value = String(character)
            if let command = symbolCommands[value] {
                return commandWithTrailingSpace(command)
            }
            return escapeMathCharacter(value)
        }.joined()
    }

    private static func commandWithTrailingSpace(_ command: String) -> String {
        guard let last = command.unicodeScalars.last,
              CharacterSet.letters.contains(last) else {
            return command
        }
        return command + " "
    }

    private static func escapeText(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            result += escapeTextCharacter(String(character))
        }
    }

    private static func escapeTextCharacter(_ value: String) -> String {
        switch value {
        case "\\": return "\\backslash "
        case "{": return "\\{"
        case "}": return "\\}"
        case "_": return "\\_"
        case "^": return "\\^{}"
        case "$": return "\\$"
        case "%": return "\\%"
        case "#": return "\\#"
        case "&": return "\\&"
        default: return value
        }
    }

    private static func escapeMathCharacter(_ value: String) -> String {
        switch value {
        case "{": return "\\{"
        case "}": return "\\}"
        case "\u{2212}": return "-"
        default: return value
        }
    }

    private static let knownOperators: Set<String> = [
        "arg", "cos", "cosh", "cot", "coth", "csc", "deg", "det", "dim",
        "exp", "gcd", "hom", "inf", "ker", "lg", "lim", "liminf", "limsup",
        "ln", "log", "max", "min", "Pr", "sec", "sin", "sinh", "sup", "tan", "tanh"
    ]

    private static let operatorCommands: [String: String] = [
        "\u{00D7}": "\\times",
        "\u{22C5}": "\\cdot",
        "\u{00F7}": "\\div",
        "\u{00B1}": "\\pm",
        "\u{2213}": "\\mp",
        "\u{2212}": "-",
        "\u{2264}": "\\le",
        "\u{2265}": "\\ge",
        "\u{2260}": "\\ne",
        "\u{2248}": "\\approx",
        "\u{2261}": "\\equiv",
        "\u{2192}": "\\to",
        "\u{2190}": "\\leftarrow",
        "\u{2194}": "\\leftrightarrow",
        "\u{21D2}": "\\Rightarrow",
        "\u{21D0}": "\\Leftarrow",
        "\u{21D4}": "\\Leftrightarrow",
        "\u{2208}": "\\in",
        "\u{2209}": "\\notin",
        "\u{2229}": "\\cap",
        "\u{222A}": "\\cup",
        "\u{2282}": "\\subset",
        "\u{2283}": "\\supset",
        "\u{2286}": "\\subseteq",
        "\u{2287}": "\\supseteq",
        "\u{221E}": "\\infty",
        "\u{2202}": "\\partial",
        "\u{2207}": "\\nabla",
        "\u{2211}": "\\sum",
        "\u{220F}": "\\prod",
        "\u{222B}": "\\int"
    ]

    private static let symbolCommands: [String: String] = [
        "\u{03B1}": "\\alpha",
        "\u{03B2}": "\\beta",
        "\u{03B3}": "\\gamma",
        "\u{03B4}": "\\delta",
        "\u{03B5}": "\\epsilon",
        "\u{03B6}": "\\zeta",
        "\u{03B7}": "\\eta",
        "\u{03B8}": "\\theta",
        "\u{03B9}": "\\iota",
        "\u{03BA}": "\\kappa",
        "\u{03BB}": "\\lambda",
        "\u{03BC}": "\\mu",
        "\u{03BD}": "\\nu",
        "\u{03BE}": "\\xi",
        "\u{03C0}": "\\pi",
        "\u{03C1}": "\\rho",
        "\u{03C3}": "\\sigma",
        "\u{03C4}": "\\tau",
        "\u{03C5}": "\\upsilon",
        "\u{03C6}": "\\phi",
        "\u{03C7}": "\\chi",
        "\u{03C8}": "\\psi",
        "\u{03C9}": "\\omega",
        "\u{0393}": "\\Gamma",
        "\u{0394}": "\\Delta",
        "\u{0398}": "\\Theta",
        "\u{039B}": "\\Lambda",
        "\u{039E}": "\\Xi",
        "\u{03A0}": "\\Pi",
        "\u{03A3}": "\\Sigma",
        "\u{03A5}": "\\Upsilon",
        "\u{03A6}": "\\Phi",
        "\u{03A8}": "\\Psi",
        "\u{03A9}": "\\Omega",
        "\u{221E}": "\\infty",
        "\u{2202}": "\\partial",
        "\u{2207}": "\\nabla",
        "\u{2113}": "\\ell"
    ]
}

private struct MathMLNode {
    let name: String
    let attributes: [String: String]
    var text: String = ""
    var children: [MathMLNode] = []

    var plainText: String {
        if children.isEmpty {
            return text
        }
        return text + children.map(\.plainText).joined()
    }
}

private final class MathMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var root: MathMLNode?
    private var stack: [MathMLNode] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalizedName(qName ?? elementName)
        var attributes: [String: String] = [:]
        for (key, value) in attributeDict {
            attributes[normalizedName(key)] = value
        }
        stack.append(MathMLNode(name: name, attributes: attributes))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard !stack.isEmpty,
              let string = String(data: CDATABlock, encoding: .utf8) else {
            return
        }
        stack[stack.count - 1].text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let completed = stack.popLast() else { return }
        if stack.isEmpty {
            root = completed
        } else {
            stack[stack.count - 1].children.append(completed)
        }
    }

    private func normalizedName(_ name: String) -> String {
        let localName = name.split(separator: ":").last.map(String.init) ?? name
        return localName.lowercased()
    }
}
