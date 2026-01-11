import Foundation
import ComplexModule
import RealModule

// ...existing code...

private enum CalculatorError: LocalizedError {
    case invalidExpression

    var errorDescription: String? {
        switch self {
        case .invalidExpression:
            return "Invalid or unsupported expression."
        }
    }
}

// Use Swift Numerics Complex type (already in the project via ComplexModule).
private typealias Complex = ComplexModule.Complex<Double>

private nonisolated struct CalculatorEngine {
    private enum Token {
        case number(Complex)
        case `operator`(String)
        case function(String)
        case leftParen
        case rightParen
    }

    private struct OperatorInfo {
        let precedence: Int
        let rightAssociative: Bool
        let apply: @Sendable (Complex, Complex) throws -> Complex
    }

    private static let operators: [String: OperatorInfo] = [
        "+": OperatorInfo(precedence: 1, rightAssociative: false, apply: { $0 + $1 }),
        "-": OperatorInfo(precedence: 1, rightAssociative: false, apply: { $0 - $1 }),
        "*": OperatorInfo(precedence: 2, rightAssociative: false, apply: { $0 * $1 }),
        "/": OperatorInfo(
            precedence: 2,
            rightAssociative: false,
            apply: { lhs, rhs in lhs / rhs }
        ),
        "^": OperatorInfo(precedence: 3, rightAssociative: true, apply: { Complex.pow($0, $1) })
    ]

    private static let functions: [String: @Sendable (Complex) -> Complex] = [
        "sin": { Complex.sin($0) },
        "cos": { Complex.cos($0) },
        "tan": { Complex.tan($0) },
        "exp": { Complex.exp($0) },
        "log": { Complex.log($0) },
        "ln": { Complex.log($0) },
        "sqrt": { Complex.sqrt($0) }
    ]

    func evaluate(_ expression: String) throws -> Complex {
        let tokens = try tokenize(expression)
        let rpn = try shuntingYard(tokens)
        return try evaluateRPN(rpn)
    }

    private func tokenize(_ input: String) throws -> [Token] {
        var result: [Token] = []
        var index = input.startIndex

        func previousIsValue() -> Bool {
            guard let last = result.last else { return false }
            switch last {
            case .number, .rightParen:
                return true
            default:
                return false
            }
        }

        while index < input.endIndex {
            let char = input[index]

            if char.isWhitespace {
                index = input.index(after: index)
                continue
            }

            // Unary minus before non-number: inject 0 - ...
            if char == "-" && !previousIsValue() {
                var lookahead = input.index(after: index)
                while lookahead < input.endIndex && input[lookahead].isWhitespace {
                    lookahead = input.index(after: lookahead)
                }
                if lookahead < input.endIndex {
                    let next = input[lookahead]
                    if !(next.isNumber || next == "." || next == "i") {
                        result.append(.number(.zero))
                        result.append(.operator("-"))
                        index = lookahead
                        continue
                    }
                }
            }

            // Number (with optional exponent) and optional trailing i.
            if char.isNumber || char == "." || (char == "-" && !previousIsValue()) {
                var end = index
                var hasImaginary = false
                var sawExponent = false

                if char == "-" { end = input.index(after: end) }

                while end < input.endIndex {
                    let next = input[end]
                    if next.isNumber || next == "." {
                        end = input.index(after: end)
                        continue
                    }
                    if next == "e" || next == "E" {
                        if sawExponent { break }
                        sawExponent = true
                        end = input.index(after: end)
                        continue
                    }
                    if (next == "+" || next == "-") && sawExponent {
                        end = input.index(after: end)
                        continue
                    }
                    if next == "i" {
                        hasImaginary = true
                        end = input.index(after: end)
                        break
                    }
                    break
                }

                let substring = input[index..<end]

                if hasImaginary {
                    let coeffStr = substring.dropLast()
                    let coeffText =
                        (coeffStr.isEmpty || coeffStr == "-") ? "\(coeffStr)1" : String(coeffStr)
                    guard let coeff = Double(coeffText) else { throw CalculatorError.invalidExpression }
                    result.append(.number(Complex(0, coeff)))
                } else {
                    guard let value = Double(substring) else { throw CalculatorError.invalidExpression }
                    result.append(.number(Complex(value, 0)))
                }

                index = end
                continue
            }

            // Identifiers: functions/constants
            if char.isLetter {
                var end = index
                while end < input.endIndex && input[end].isLetter { end = input.index(after: end) }
                let name = input[index..<end].lowercased()

                switch name {
                case "pi":
                    result.append(.number(Complex(Double.pi, 0)))
                case "e":
                    result.append(.number(Complex(Foundation.exp(1), 0)))
                case "i":
                    result.append(.number(Complex(0, 1)))
                default:
                    guard Self.functions[name] != nil else { throw CalculatorError.invalidExpression }
                    result.append(.function(name))
                }

                index = end
                continue
            }

            switch char {
            case "+": result.append(.operator("+"))
            case "-": result.append(.operator("-"))
            case "*": result.append(.operator("*"))
            case "/": result.append(.operator("/"))
            case "^": result.append(.operator("^"))
            case "(": result.append(.leftParen)
            case ")": result.append(.rightParen)
            default:
                throw CalculatorError.invalidExpression
            }

            index = input.index(after: index)
        }

        return result
    }

    private func shuntingYard(_ tokens: [Token]) throws -> [Token] {
        var output: [Token] = []
        var stack: [Token] = []

        for token in tokens {
            switch token {
            case .number:
                output.append(token)

            case .function:
                stack.append(token)

            case .operator(let symbol):
                guard let opInfo = Self.operators[symbol] else { throw CalculatorError.invalidExpression }

                while let top = stack.last {
                    switch top {
                    case .operator(let topSymbol):
                        guard let topInfo = Self.operators[topSymbol] else { break }
                        if (opInfo.rightAssociative && opInfo.precedence < topInfo.precedence)
                            || (!opInfo.rightAssociative && opInfo.precedence <= topInfo.precedence) {
                            output.append(stack.removeLast())
                            continue
                        }

                    case .function:
                        output.append(stack.removeLast())
                        continue

                    default:
                        break
                    }
                    break
                }

                stack.append(token)

            case .leftParen:
                stack.append(token)

            case .rightParen:
                while let last = stack.last {
                    if case .leftParen = last { break }
                    output.append(stack.removeLast())
                }
                guard stack.last != nil else { throw CalculatorError.invalidExpression }
                _ = stack.removeLast()  // pop left paren

                if let last = stack.last, case .function = last {
                    output.append(stack.removeLast())
                }
            }
        }

        while let last = stack.popLast() {
            if case .leftParen = last { throw CalculatorError.invalidExpression }
            output.append(last)
        }

        return output
    }

    private func evaluateRPN(_ tokens: [Token]) throws -> Complex {
        var stack: [Complex] = []

        for token in tokens {
            switch token {
            case .number(let value):
                stack.append(value)

            case .operator(let symbol):
                guard let opInfo = Self.operators[symbol], let rhs = stack.popLast(),
                    let lhs = stack.popLast()
                else {
                    throw CalculatorError.invalidExpression
                }
                stack.append(try opInfo.apply(lhs, rhs))

            case .function(let name):
                guard let value = stack.popLast(), let mathFunction = Self.functions[name] else {
                    throw CalculatorError.invalidExpression
                }
                stack.append(mathFunction(value))

            default:
                throw CalculatorError.invalidExpression
            }
        }

        guard stack.count == 1, let result = stack.first else {
            throw CalculatorError.invalidExpression
        }

        return result
    }
}

private nonisolated func formatComplex(_ value: Complex, precision: Int, style: String) -> String {
    let epsilon = 1e-10

    func format(_ number: Double) -> String {
        if number.isNaN { return "nan" }
        if number.isInfinite { return number.sign == .minus ? "-inf" : "inf" }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = min(max(0, precision), 12)
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = style == "scientific" ? .scientific : .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    if abs(value.imaginary) < epsilon {
        return format(value.real)
    }

    let realPart = abs(value.real) < epsilon ? "0" : format(value.real)
    let imagPart = format(abs(value.imaginary))
    let sign = value.imaginary >= 0 ? "+" : "-"
    return "\(realPart) \(sign) \(imagPart)i"
}

// MARK: - Tool

nonisolated struct CalculatorTool: Tool {
    let name = "calculator"
    let description = "Evaluates mathematical expressions with scientific functions and complex numbers."

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "expression": ToolProperty(
                    type: .string,
                    description:
                        "The mathematical expression to evaluate (e.g., '5 * 5 + 2', 'sin(pi/4)')"
                ),
                "precision": ToolProperty(
                    type: .integer,
                    description: "Decimal precision (0-12, default 6)"
                ),
                "format": ToolProperty(
                    type: .string,
                    description: "Output format (default: decimal)",
                    enumValues: ["decimal", "scientific"]
                )
            ],
            required: ["expression"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .safe
    let requiredCapabilities: [ToolCapability] = []
    let weight: ToolWeight = .fast
    let isCacheable = true

    init() {}

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let expression = arguments.string("expression") else {
            throw ToolError.invalidArguments("Missing 'expression' string")
        }

        do {
            let precision = min(max(arguments.int("precision") ?? 6, 0), 12)
            let formatStyle = arguments.string("format")?.lowercased() ?? "decimal"

            let result = try CalculatorEngine().evaluate(expression)
            let formatted = formatComplex(result, precision: precision, style: formatStyle)
            return ToolResult.success(formatted)
        } catch let error as CalculatorError {
            throw ToolError.executionFailed(error.localizedDescription)
        } catch {
            throw ToolError.executionFailed(
                "Could not evaluate expression: \(error.localizedDescription)"
            )
        }
    }
}
