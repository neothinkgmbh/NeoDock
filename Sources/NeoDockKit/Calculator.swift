import Foundation

/// Kleiner Rechner mit eigenem Parser (rekursiver Abstieg). Bewusst kein NSExpression:
/// das wirft bei ungültiger Eingabe Objective-C-Ausnahmen, die Swift nicht fangen kann.
/// Unterstützt + − × ÷ ^ %, Klammern, Vorzeichen, Komma oder Punkt als Dezimaltrenner.
public enum Calculator {
    public enum Failure: Error, Equatable { case empty, unexpected(String), divisionByZero, incomplete }

    public static func evaluate(_ text: String) throws(Failure) -> Double {
        var parser = Parser(tokens: try tokenize(text))
        guard !parser.tokens.isEmpty else { throw .empty }
        let value = try parser.expression()
        guard parser.index == parser.tokens.count else { throw .unexpected(parser.tokens[parser.index].text) }
        guard value.isFinite else { throw .divisionByZero }
        return value
    }

    static let maxFractionDigits = 10

    public static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).grouping(.never)
            .locale(Locale(identifier: "de_AT")))
    }

    enum Token: Equatable {
        case number(Double), op(Character), open, close
        var text: String {
            switch self {
            case .number(let n): "\(n)"
            case .op(let c): String(c)
            case .open: "("
            case .close: ")"
            }
        }
    }

    static func tokenize(_ text: String) throws(Failure) -> [Token] {
        var tokens: [Token] = []
        var number = ""
        func flush() throws(Failure) {
            guard !number.isEmpty else { return }
            guard let value = Double(number.replacingOccurrences(of: ",", with: ".")) else { throw .unexpected(number) }
            tokens.append(.number(value))
            number = ""
        }
        for char in text {
            switch char {
            case "0"..."9", ".", ",": number.append(char)
            case " ": try flush()
            case "+", "-", "*", "/", "^", "%", "×", "÷", "−":
                try flush()
                let normalized: Character = ["×": "*", "÷": "/", "−": "-"][char] ?? char
                tokens.append(.op(normalized))
            case "(": try flush(); tokens.append(.open)
            case ")": try flush(); tokens.append(.close)
            default: throw .unexpected(String(char))
            }
        }
        try flush()
        return tokens
    }

    struct Parser {
        let tokens: [Token]
        var index = 0

        mutating func next() -> Token? {
            defer { index += 1 }
            return index < tokens.count ? tokens[index] : nil
        }

        func peek() -> Token? { index < tokens.count ? tokens[index] : nil }

        // expression := term (('+' | '-') term)*
        mutating func expression() throws(Failure) -> Double {
            var value = try term()
            while case .op(let op)? = peek(), op == "+" || op == "-" {
                index += 1
                let rhs = try term()
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        // term := power (('*' | '/') power)*
        mutating func term() throws(Failure) -> Double {
            var value = try power()
            while case .op(let op)? = peek(), op == "*" || op == "/" {
                index += 1
                let rhs = try power()
                if op == "/" && rhs == 0 { throw .divisionByZero }
                value = op == "*" ? value * rhs : value / rhs
            }
            return value
        }

        // power := unary ('^' power)?   (rechtsassoziativ)
        mutating func power() throws(Failure) -> Double {
            let base = try unary()
            if case .op("^")? = peek() {
                index += 1
                return pow(base, try power())
            }
            return base
        }

        // unary := '-' unary | postfix
        mutating func unary() throws(Failure) -> Double {
            if case .op("-")? = peek() { index += 1; return -(try unary()) }
            if case .op("+")? = peek() { index += 1; return try unary() }
            return try postfix()
        }

        // postfix := primary '%'*
        mutating func postfix() throws(Failure) -> Double {
            var value = try primary()
            while case .op("%")? = peek() { index += 1; value /= 100 }
            return value
        }

        mutating func primary() throws(Failure) -> Double {
            switch next() {
            case .number(let value)?: return value
            case .open?:
                let value = try expression()
                guard case .close? = next() else { throw .incomplete }
                return value
            case let token?: throw .unexpected(token.text)
            case nil: throw .incomplete
            }
        }
    }
}
