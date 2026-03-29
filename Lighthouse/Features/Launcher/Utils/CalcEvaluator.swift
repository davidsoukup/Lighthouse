import Foundation

struct CalcEvaluator {
    static func evaluate(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { return nil }

        let allowed = CharacterSet(charactersIn: "0123456789+-*/%.() ,")
        if trimmed.rangeOfCharacter(from: allowed.inverted) != nil { return nil }

        let expr = trimmed.replacingOccurrences(of: ",", with: ".")
        guard hasOperator(expr) else { return nil }
        guard let value = evalExpression(expr), value.isFinite else { return nil }
        return formatNumber(value)
    }

    private static func evalExpression(_ s: String) -> Double? {
        let trimmed = trimTrailingOperators(s)
        if isSafeExpression(trimmed), let v = evalRaw(trimmed) { return v }
        return nil
    }

    private static func evalRaw(_ s: String) -> Double? {
        let nsExpr = NSExpression(format: s)
        if let num = nsExpr.expressionValue(with: nil, context: nil) as? NSNumber {
            return num.doubleValue
        }
        return nil
    }

    private static func trimTrailingOperators(_ s: String) -> String {
        var out = s
        while let last = out.last {
            if last == " " { out.removeLast(); continue }
            if last == "+" || last == "-" || last == "*" || last == "/" || last == "%" || last == "." {
                out.removeLast()
                continue
            }
            break
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasOperator(_ s: String) -> Bool {
        var depth = 0
        for ch in s {
            if ch == "(" { depth += 1; continue }
            if ch == ")" { depth = max(0, depth - 1); continue }
            if depth > 0 { continue }
            if ch == "+" || ch == "-" || ch == "*" || ch == "/" || ch == "%" {
                return true
            }
        }
        return false
    }

    private static func isSafeExpression(_ s: String) -> Bool {
        if s.isEmpty { return false }
        var depth = 0
        var prevWasOp = true
        for ch in s {
            if ch == " " { continue }
            if ch.isNumber || ch == "." {
                prevWasOp = false
                continue
            }
            if ch == "(" {
                depth += 1
                prevWasOp = true
                continue
            }
            if ch == ")" {
                depth -= 1
                if depth < 0 { return false }
                prevWasOp = false
                continue
            }
            if ch == "+" || ch == "-" || ch == "*" || ch == "/" || ch == "%" {
                if prevWasOp && ch != "-" {
                    return false
                }
                prevWasOp = true
                continue
            }
            return false
        }
        if depth != 0 { return false }
        if prevWasOp { return false }
        return true
    }

    private static func formatNumber(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(v))
        }
        let fmt = NumberFormatter()
        fmt.maximumFractionDigits = 6
        fmt.minimumFractionDigits = 0
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: v)) ?? String(v)
    }
}
