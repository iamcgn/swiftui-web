// A Cassowary linear constraint solver (Badros, Borning and Stuckey, 2001), in the incremental
// simplex form of Kiwi: the tableau keeps every basic symbol's row, an objective of weighted
// error symbols for the non-required constraints, and pivots to keep the rows feasible. UIKit's
// Auto Layout is Cassowary; this is what solves `NSLayoutConstraint`s (decision 0014, Phase 3).
//
// Constraints are added once per layout pass to a fresh solver (no removal), so the
// implementation stays small: `add(_:)`, `solve()`, `value(of:)`.

/// A quantity the solver finds a value for.
final class LayoutVariable: Hashable {
    let name: String
    fileprivate(set) var value: Double = 0

    init(_ name: String) { self.name = name }

    static func == (lhs: LayoutVariable, rhs: LayoutVariable) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// A linear expression: a constant plus weighted variables.
struct LinearExpression {
    var terms: [LayoutVariable: Double] = [:]
    var constant: Double = 0

    init(constant: Double = 0) { self.constant = constant }

    init(_ variable: LayoutVariable, coefficient: Double = 1, constant: Double = 0) {
        terms[variable] = coefficient
        self.constant = constant
    }

    static func + (lhs: LinearExpression, rhs: LinearExpression) -> LinearExpression {
        var result = lhs
        for (variable, coefficient) in rhs.terms { result.terms[variable, default: 0] += coefficient }
        result.constant += rhs.constant
        return result
    }

    static func - (lhs: LinearExpression, rhs: LinearExpression) -> LinearExpression { lhs + rhs * Double(-1) }

    static func * (lhs: LinearExpression, rhs: Double) -> LinearExpression {
        var result = lhs
        for variable in Array(result.terms.keys) { result.terms[variable]! *= rhs }
        result.constant *= rhs
        return result
    }

    static func + (lhs: LinearExpression, rhs: Double) -> LinearExpression {
        var result = lhs
        result.constant += rhs
        return result
    }

    static func - (lhs: LinearExpression, rhs: Double) -> LinearExpression { lhs + (-rhs) }

    // Where CGFloat is its own type (Apple platforms); on wasm and Linux it is Double.
    #if canImport(CoreGraphics)
    static func + (lhs: LinearExpression, rhs: CGFloat) -> LinearExpression { lhs + Double(rhs) }
    static func - (lhs: LinearExpression, rhs: CGFloat) -> LinearExpression { lhs + Double(-rhs) }
    static func * (lhs: LinearExpression, rhs: CGFloat) -> LinearExpression { lhs * Double(rhs) }
    #endif
}

/// How a constraint relates its expression to zero.
enum LayoutRelation {
    case lessThanOrEqual, equal, greaterThanOrEqual
}

/// A constraint `expression (op) 0` with a strength: `LayoutStrength.required`, or a weight; a
/// stronger constraint is satisfied before any number of weaker ones as far as the weights'
/// ratios carry (UIKit priorities map to exponentially spaced weights).
struct LayoutConstraintRow {
    var expression: LinearExpression
    var relation: LayoutRelation
    var strength: Double
}

enum LayoutStrength {
    static let required = Double.greatestFiniteMagnitude

    /// The weight of a UIKit priority: 1000 is required; below, ten to the priority over a
    /// hundred, so 750 outweighs 250 a hundred-thousandfold and 999 still beats 998.
    static func weight(priority: Float) -> Double {
        if priority >= 1000 { return required }
        return _pow(10, Double(max(1, priority)) / 100)
    }
}

/// The solver. Symbols name the tableau's columns: the external variables, slack and error
/// variables of inequalities and non-required constraints, and dummies marking required
/// equalities.
final class CassowarySolver {
    private struct Symbol: Hashable {
        enum Kind { case invalid, external, slack, error, dummy }
        let id: Int
        let kind: Kind
        static let invalid = Symbol(id: 0, kind: .invalid)
    }

    private struct Row {
        var cells: [Symbol: Double] = [:]
        var constant: Double = 0

        init(constant: Double = 0) { self.constant = constant }

        mutating func insert(_ symbol: Symbol, _ coefficient: Double = 1) {
            let value = (cells[symbol] ?? 0) + coefficient
            if nearZero(value) { cells.removeValue(forKey: symbol) } else { cells[symbol] = value }
        }

        mutating func insert(_ other: Row, _ coefficient: Double) {
            constant += other.constant * coefficient
            for (symbol, value) in other.cells { insert(symbol, value * coefficient) }
        }

        mutating func remove(_ symbol: Symbol) { cells.removeValue(forKey: symbol) }

        mutating func reverseSign() {
            constant = -constant
            for symbol in Array(cells.keys) { cells[symbol]! = -cells[symbol]! }
        }

        /// Makes `symbol` the subject: the row becomes `symbol = ...`.
        mutating func solve(for symbol: Symbol) {
            let coefficient = -1 / cells[symbol]!
            cells.removeValue(forKey: symbol)
            constant *= coefficient
            for key in Array(cells.keys) { cells[key]! *= coefficient }
        }

        mutating func solve(for lhs: Symbol, _ rhs: Symbol) {
            insert(lhs, -1)
            solve(for: rhs)
        }

        func coefficient(for symbol: Symbol) -> Double { cells[symbol] ?? 0 }

        mutating func substitute(_ symbol: Symbol, with row: Row) {
            if let coefficient = cells.removeValue(forKey: symbol) { insert(row, coefficient) }
        }
    }

    private var rows: [Symbol: Row] = [:]
    private var variables: [LayoutVariable: Symbol] = [:]
    private var objective = Row()
    private var artificial: Row?
    private var nextSymbolID = 1
    private var infeasibleRows: [Symbol] = []

    init() {}

    private func newSymbol(_ kind: Symbol.Kind) -> Symbol {
        defer { nextSymbolID += 1 }
        return Symbol(id: nextSymbolID, kind: kind)
    }

    private func symbol(for variable: LayoutVariable) -> Symbol {
        if let symbol = variables[variable] { return symbol }
        let symbol = newSymbol(.external)
        variables[variable] = symbol
        return symbol
    }

    /// Adds a constraint; returns false when a required constraint cannot be satisfied (the
    /// constraint is then ignored, as UIKit breaks one).
    @discardableResult
    func add(_ constraint: LayoutConstraintRow) -> Bool {
        var row = Row(constant: constraint.expression.constant)
        for (variable, coefficient) in constraint.expression.terms where !nearZero(coefficient) {
            let symbol = symbol(for: variable)
            if let basic = rows[symbol] { row.insert(basic, coefficient) } else { row.insert(symbol, coefficient) }
        }
        var marker = Symbol.invalid
        var other = Symbol.invalid
        let required = constraint.strength == LayoutStrength.required
        switch constraint.relation {
        case .lessThanOrEqual, .greaterThanOrEqual:
            let coefficient: Double = constraint.relation == .lessThanOrEqual ? 1 : -1
            marker = newSymbol(.slack)
            row.insert(marker, coefficient)
            if !required {
                other = newSymbol(.error)
                row.insert(other, -coefficient)
                objective.insert(other, constraint.strength)
            }
        case .equal:
            if required {
                marker = newSymbol(.dummy)
                row.insert(marker)
            } else {
                marker = newSymbol(.error)
                other = newSymbol(.error)
                row.insert(marker, -1)
                row.insert(other, 1)
                objective.insert(marker, constraint.strength)
                objective.insert(other, constraint.strength)
            }
        }
        if row.constant < 0 { row.reverseSign() }

        var subject = chooseSubject(row, marker: marker, other: other)
        if subject.kind == .invalid, row.cells.keys.allSatisfy({ $0.kind == .dummy }) {
            // Only dummies left: satisfiable exactly when the constant is zero.
            if !nearZero(row.constant) { return false }
            subject = marker
        }
        if subject.kind == .invalid {
            guard addWithArtificialVariable(row) else { return false }
        } else {
            row.solve(for: subject)
            substitute(subject, with: row)
            rows[subject] = row
        }
        optimize(.main)
        return true
    }

    /// Which row a pivot minimises: the objective, or the artificial row while adding a
    /// constraint with an artificial variable.
    private enum Target { case main, artificial }

    private func chooseSubject(_ row: Row, marker: Symbol, other: Symbol) -> Symbol {
        for symbol in row.cells.keys.sorted(by: { $0.id < $1.id }) where symbol.kind == .external { return symbol }
        if marker.kind == .slack || marker.kind == .error, row.coefficient(for: marker) < 0 { return marker }
        if other.kind == .slack || other.kind == .error, row.coefficient(for: other) < 0 { return other }
        return .invalid
    }

    private func addWithArtificialVariable(_ row: Row) -> Bool {
        let art = newSymbol(.slack)
        rows[art] = row
        artificial = row
        optimize(.artificial)
        let success = nearZero(artificial!.constant)
        artificial = nil
        if var basic = rows.removeValue(forKey: art) {
            if basic.cells.isEmpty { return success }
            guard let entering = basic.cells.keys.sorted(by: { $0.id < $1.id }).first(where: { $0.kind == .slack || $0.kind == .error }) else { return false }
            basic.solve(for: art, entering)
            substitute(entering, with: basic)
            rows[entering] = basic
        }
        for key in Array(rows.keys) { rows[key]!.remove(art) }
        objective.remove(art)
        return success
    }

    private func substitute(_ symbol: Symbol, with row: Row) {
        for key in Array(rows.keys) {
            rows[key]!.substitute(symbol, with: row)
            if key.kind != .external, rows[key]!.constant < 0 { infeasibleRows.append(key) }
        }
        objective.substitute(symbol, with: row)
        artificial?.substitute(symbol, with: row)
    }

    private func optimize(_ target: Target) {
        while true {
            // Read the row afresh each pivot: `substitute` rewrites it.
            guard let objective = target == .main ? self.objective : artificial else { return }
            guard let entering = objective.cells.keys.sorted(by: { $0.id < $1.id }).first(where: { $0.kind != .dummy && objective.cells[$0]! < 0 }) else { return }
            var ratio = Double.greatestFiniteMagnitude
            var leaving = Symbol.invalid
            for (symbol, row) in rows where symbol.kind != .external {
                let coefficient = row.coefficient(for: entering)
                if coefficient < 0 {
                    let candidate = -row.constant / coefficient
                    if candidate < ratio || (candidate == ratio && symbol.id < leaving.id) {
                        ratio = candidate
                        leaving = symbol
                    }
                }
            }
            guard leaving.kind != .invalid, var row = rows.removeValue(forKey: leaving) else { return }
            row.solve(for: leaving, entering)
            substitute(entering, with: row)
            rows[entering] = row
        }
    }

    /// Reads every variable's value from the tableau.
    func solve() {
        for (variable, symbol) in variables {
            variable.value = rows[symbol]?.constant ?? 0
        }
    }

    func value(of variable: LayoutVariable) -> Double {
        guard let symbol = variables[variable] else { return 0 }
        return rows[symbol]?.constant ?? 0
    }
}

private func nearZero(_ value: Double) -> Bool { abs(value) < 1e-8 }
