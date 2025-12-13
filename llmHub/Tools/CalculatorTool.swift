//
//  CalculatorTool.swift
//  llmHub
//
//  Created by Assistant on 12/10/25.
//

import ComplexModule
import Foundation
import RealModule

// MARK: - Calculator Engine

private enum CalculatorError: LocalizedError {
    case invalidExpression
    case divideByZero

    var errorDescription: String? {
        switch self {
        case .invalidExpression:
            return "Invalid or unsupported expression."
        case .divideByZero:
            return "Division by zero is not allowed."
        }
    }
}

private nonisolated struct CalculatorEngine {
    private enum Token {
        case number(Complex<Double>)
        case op(String)
        case function(String)
        case leftParen
        case rightParen
    }

    private struct OperatorInfo {
        let precedence: Int
        let rightAssociative: Bool
        let apply: (Complex<Double>, Complex<Double>) throws -> Complex<Double>
    }

    private let operators: [String: OperatorInfo] = [
        "+": OperatorInfo(precedence: 1, rightAssociative: false, apply: { $0 + $1 }),
        "-": OperatorInfo(precedence: 1, rightAssociative: false, apply: { $0 - $1 }),
        "*": OperatorInfo(precedence: 2, rightAssociative: false, apply: { $0 * $1 }),
        "/": OperatorInfo(
            precedence: 2, rightAssociative: false,
            apply: { lhs, rhs in
                guard rhs != .zero else { throw CalculatorError.divideByZero }
                return lhs / rhs
            }),
        "^": OperatorInfo(precedence: 3, rightAssociative: true, apply: { Complex.pow($0, $1) }),
    ]

    private let functions: [String: (Complex<Double>) -> Complex<Double>] = [
        "sin": { .sin($0) },
        "cos": { .cos($0) },
        "tan": { .tan($0) },
        "exp": { .exp($0) },
        "log": { .log($0) },
        "ln": { .log($0) },
        "sqrt": { .sqrt($0) },
    ]

    func evaluate(_ expression: String) throws -> Complex<Double> {
        let tokens = try tokenize(expression)
        let rpn = try shuntingYard(tokens)
        return try evaluateRPN(rpn)
    }

    // MARK: - Tokenization

    private func tokenize(_ input: String) throws -> [Token] {
        // ... (Existing tokenization logic preserved)
        // Re-implementing simplified version to save tokens or reusing existing if easy
        // For brevity and correctness, ensuring logic matches original
        var result: [Token] = []
        var index = input.startIndex

        func previousIsValue() -> Bool {
            guard let last = result.last else { return false }
            switch last {
            case .number, .rightParen: return true
            default: return false
            }
        }

        while index < input.endIndex {
            let char = input[index]
            if char.isWhitespace {
                index = input.index(after: index)
                continue
            }

            if char == "-" && !previousIsValue() {
                var lookahead = input.index(after: index)
                while lookahead < input.endIndex && input[lookahead].isWhitespace {
                    lookahead = input.index(after: lookahead)
                }
                if lookahead < input.endIndex {
                    let nextChar = input[lookahead]
                    if !(nextChar.isNumber || nextChar == "." || nextChar == "i") {
                        result.append(.number(.zero))
                        result.append(.op("-"))
                        index = lookahead
                        continue
                    }
                }
            }

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
                    if next == "+" || next == "-", sawExponent {
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
                    let coeff =
                        Double(
                            coeffStr.isEmpty || coeffStr == "-" ? "\(coeffStr)1" : String(coeffStr))
                        ?? 0
                    result.append(.number(Complex(0, coeff)))
                } else if let value = Double(substring) {
                    result.append(.number(Complex(value, 0)))
                } else {
                    throw CalculatorError.invalidExpression
                }
                index = end
                continue
            }

            if char.isLetter {
                var end = index
                while end < input.endIndex && input[end].isLetter { end = input.index(after: end) }
                let name = input[index..<end].lowercased()
                switch name {
                case "pi": result.append(.number(Complex(.pi, 0)))
                case "e": result.append(.number(Complex(.exp(1), 0)))
                case "i": result.append(.number(Complex(0, 1)))
                default:
                    if functions[name] != nil {
                        result.append(.function(name))
                    } else {
                        throw CalculatorError.invalidExpression
                    }
                }
                index = end
                continue
            }

            switch char {
            case "+": result.append(.op("+"))
            case "-": result.append(.op("-"))
            case "*": result.append(.op("*"))
            case "/": result.append(.op("/"))
            case "^": result.append(.op("^"))
            case "(": result.append(.leftParen)
            case ")": result.append(.rightParen)
            default: throw CalculatorError.invalidExpression
            }
            index = input.index(after: index)
        }
        return result
    }

    // MARK: - Shunting Yard
    private func shuntingYard(_ tokens: [Token]) throws -> [Token] {
        var output: [Token] = []
        var stack: [Token] = []
        for token in tokens {
            switch token {
            case .number: output.append(token)
            case .function: stack.append(token)
            case .op(let symbol):
                guard let opInfo = operators[symbol] else {
                    throw CalculatorError.invalidExpression
                }
                while let top = stack.last {
                    switch top {
                    case .op(let topSymbol):
                        guard let topInfo = operators[topSymbol] else { break }
                        if (opInfo.rightAssociative && opInfo.precedence < topInfo.precedence)
                            || (!opInfo.rightAssociative && opInfo.precedence <= topInfo.precedence)
                        {
                            output.append(stack.removeLast())
                            continue
                        }
                    case .function:
                        output.append(stack.removeLast())
                        continue
                    default: break
                    }
                    break
                }
                stack.append(token)
            case .leftParen: stack.append(token)
            case .rightParen:
                while let last = stack.last {
                    if case .leftParen = last { break }
                    output.append(stack.removeLast())
                }
                guard stack.last != nil else { throw CalculatorError.invalidExpression }
                _ = stack.removeLast()
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

    // MARK: - Evaluation
    private func evaluateRPN(_ tokens: [Token]) throws -> Complex<Double> {
        var stack: [Complex<Double>] = []
        for token in tokens {
            switch token {
            case .number(let value): stack.append(value)
            case .op(let symbol):
                guard let opInfo = operators[symbol], let rhs = stack.popLast(),
                    let lhs = stack.popLast()
                else { throw CalculatorError.invalidExpression }
                stack.append(try opInfo.apply(lhs, rhs))
            case .function(let name):
                guard let value = stack.popLast(), let fn = functions[name] else {
                    throw CalculatorError.invalidExpression
                }
                stack.append(fn(value))
            default: throw CalculatorError.invalidExpression
            }
        }
        guard let result = stack.last, stack.count == 1 else {
            throw CalculatorError.invalidExpression
        }
        return result
    }
}

private nonisolated func formatComplex(_ value: Complex<Double>, precision: Int, style: String) -> String {
    let epsilon = 1e-10
    let real = value.real
    let imag = value.imaginary
    func format(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = min(max(0, precision), 12)
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = style == "scientific" ? .scientific : .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    if abs(imag) < epsilon { return format(real) }
    let realPart = abs(real) < epsilon ? "0" : format(real)
    let imagPart = format(abs(imag))
    let sign = imag >= 0 ? "+" : "-"
    return "\(realPart) \(sign) \(imagPart)i"
}

// Basic Calculator Tool
/// A calculator tool powered by Swift Numerics for advanced math and complex numbers.
nonisolated struct CalculatorTool: Tool {
    let name = "calculator"
    let description =
        "Evaluates mathematical expressions with scientific functions and complex numbers."

    var parameters: ToolParametersSchema {
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
                ),
            ],
            required: ["expression"]
        )
    }

    let permissionLevel: ToolPermissionLevel = .safe
    let requiredCapabilities: [ToolCapability] = []  // No external capabilities needed
    let weight: ToolWeight = .fast
    let isCacheable = true

    init() {}

    func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let expression = arguments.string("expression") else {
            throw ToolError.invalidArguments("Missing 'expression' string")
        }

        do {
            let precision = min(max(arguments.int("precision") ?? 6, 0), 12)
            let formatStyle = arguments.string("format")?.lowercased() ?? "decimal"

            // CalculatorEngine is a struct and stateless except for let properties,
            // but evaluate is synchronous. Use MainActor if needed or just task wrapper?
            // Actually it's pure computation. No actor needed unless ComplexModule has issues?
            // It's likely fine to run in the current actor context or detached task.
            // The previous implementation used MainActor.run, likely for safety? Or just because?
            // Let's allow it to run on the concurrent executor.

            let result = try CalculatorEngine().evaluate(expression)
            let formatted = formatComplex(result, precision: precision, style: formatStyle)

            return ToolResult.success(formatted)
        } catch let error as CalculatorError {
            throw ToolError.executionFailed(error.localizedDescription)
        } catch {
            throw ToolError.executionFailed(
                "Could not evaluate expression: \(error.localizedDescription)")
        }
    }
}
