// The engine behind JavaScriptCore on the web: the browser's own JavaScript, reached through
// JavaScriptKit. Each context is a realm of its own, a hidden same-origin `<iframe>` whose window
// is the context's global object, so the scripts an app evaluates (highlight.js, a template
// engine) declare their globals there and never on the page's window. Where there is no
// document to make a frame in (a worker, the test runner under Node) every context shares the
// one global object. Every operation that runs script (an evaluation, a call, a getter) runs
// inside a `try`, so an exception comes back to Swift as a value, as JavaScriptCore reports it.
// Without a browser (the native builds) there is no engine: a context cannot be made.
#if os(WASI)
import JavaScriptKit

/// A value of the engine (JavaScriptKit's), as a context's values hold it.
typealias _JSHandle = JavaScriptKit.JSValue

enum _JSEngine {
    /// What an operation that may throw gives back: its value, or the exception it threw.
    enum Outcome {
        case value(_JSHandle)
        case exception(_JSHandle)
    }

    /// The helpers, made once in the page's realm; each takes the realm's global object where
    /// it makes something, so a new object, array or date belongs to the context's realm.
    nonisolated(unsafe) private static let helpers: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        let body = """
        var guard = function (f) { try { return { ok: true, v: f() }; } catch (e) { return { ok: false, v: e }; } };
        var tag = typeof Symbol === 'function' ? Symbol.for('swiftui-web.javascriptcore.wrapper') : '__swiftWrapper';
        return {
          realm: function () {
            if (typeof document !== 'undefined' && document.createElement && (document.body || document.documentElement)) {
              var frame = document.createElement('iframe');
              frame.setAttribute('aria-hidden', 'true');
              frame.setAttribute('tabindex', '-1');
              frame.style.display = 'none';
              (document.body || document.documentElement).appendChild(frame);
              if (frame.contentWindow) return { global: frame.contentWindow, frame: frame };
              frame.parentNode.removeChild(frame);
            }
            return { global: globalThis, frame: null };
          },
          drop: function (realm) { if (realm.frame && realm.frame.parentNode) realm.frame.parentNode.removeChild(realm.frame); },
          evaluate: function (g, source) { return guard(function () { return g.eval(source); }); },
          get: function (o, k) { return guard(function () { return o[k]; }); },
          set: function (o, k, v) { return guard(function () { o[k] = v; return undefined; }); },
          remove: function (o, k) { return guard(function () { return delete o[k]; }); },
          has: function (o, k) { return guard(function () { return k in Object(o); }); },
          define: function (o, k, d) { return guard(function () { Object.defineProperty(o, k, d); return undefined; }); },
          call: function (f, self, args) { return guard(function () { return Reflect.apply(f, self, args); }); },
          construct: function (f, args) { return guard(function () { return Reflect.construct(f, args); }); },
          invoke: function (o, name, args) { return guard(function () { var f = o[name]; return Reflect.apply(f, o, args); }); },
          kind: function (v) {
            if (v === undefined) return 'undefined';
            if (v === null) return 'null';
            var t = typeof v;
            if (t === 'boolean' || t === 'number' || t === 'string' || t === 'symbol' || t === 'bigint') return t;
            if (Array.isArray(v)) return 'array';
            if (Object.prototype.toString.call(v) === '[object Date]') return 'date';
            if (t === 'function') return 'function';
            return 'object';
          },
          text: function (v) { return guard(function () { return typeof v === 'symbol' ? v.toString() : String(v); }); },
          number: function (v) { try { return typeof v === 'bigint' ? Number(v) : Number(v); } catch (e) { return NaN; } },
          int32: function (v) { try { return Number(v) | 0; } catch (e) { return 0; } },
          uint32: function (v) { try { return Number(v) >>> 0; } catch (e) { return 0; } },
          truth: function (v) { return !!v; },
          same: function (a, b) { return a === b; },
          loose: function (a, b) { try { return a == b; } catch (e) { return false; } },
          instance: function (v, c) { try { return v instanceof c; } catch (e) { return false; } },
          keys: function (o) { try { return Object.keys(o); } catch (e) { return []; } },
          length: function (o) { try { var n = o.length; return typeof n === 'number' ? n : -1; } catch (e) { return -1; } },
          object: function (g) { return new g.Object(); },
          array: function (g) { return new g.Array(); },
          date: function (g, ms) { return new g.Date(ms); },
          error: function (g, message) { return new g.Error(message); },
          symbol: function (g, d) { return g.Symbol(d); },
          regexp: function (g, p, f) { return guard(function () { return new g.RegExp(p, f); }); },
          resolved: function (g, v) { return g.Promise.resolve(v); },
          rejected: function (g, v) { return g.Promise.reject(v); },
          wrap: function (g, id) { var o = new g.Object(); Object.defineProperty(o, tag, { value: id }); return o; },
          wrapped: function (o) { try { var id = o[tag]; return typeof id === 'number' ? id : -1; } catch (e) { return -1; } }
        };
        """
        guard let factory = try? make.throws.new(body) else { return nil }
        return factory().object
    }()

    static var available: Bool { helpers != nil }

    private static func helper(_ name: String) -> JSObject { helpers![name].object! }

    private static func outcome(_ result: _JSHandle) -> Outcome {
        guard let object = result.object else { return .value(.undefined) }
        return object["ok"].boolean == true ? .value(object["v"]) : .exception(object["v"])
    }

    // MARK: Realms

    /// A new realm: its global object, and what drops it.
    static func makeRealm() -> (global: JSObject, realm: JSObject)? {
        guard available, let realm = helper("realm")().object, let global = realm["global"].object else { return nil }
        return (global, realm)
    }

    static func dropRealm(_ realm: JSObject) { _ = helper("drop")(realm) }

    // MARK: Running script

    static func evaluate(_ source: String, in global: JSObject) -> Outcome { outcome(helper("evaluate")(global, source)) }
    static func get(_ object: _JSHandle, _ key: _JSHandle) -> Outcome { outcome(helper("get")(object, key)) }
    static func set(_ object: _JSHandle, _ key: _JSHandle, _ value: _JSHandle) -> Outcome { outcome(helper("set")(object, key, value)) }
    static func remove(_ object: _JSHandle, _ key: _JSHandle) -> Outcome { outcome(helper("remove")(object, key)) }
    static func has(_ object: _JSHandle, _ key: _JSHandle) -> Outcome { outcome(helper("has")(object, key)) }
    static func define(_ object: _JSHandle, _ key: _JSHandle, _ descriptor: _JSHandle) -> Outcome {
        outcome(helper("define")(object, key, descriptor))
    }
    static func call(_ function: _JSHandle, this: _JSHandle, _ arguments: [_JSHandle]) -> Outcome {
        outcome(helper("call")(function, this, array(arguments)))
    }
    static func construct(_ function: _JSHandle, _ arguments: [_JSHandle]) -> Outcome {
        outcome(helper("construct")(function, array(arguments)))
    }
    static func invoke(_ object: _JSHandle, _ method: String, _ arguments: [_JSHandle]) -> Outcome {
        outcome(helper("invoke")(object, method, array(arguments)))
    }

    /// A plain array of the page's realm holding `values` (the argument lists).
    private static func array(_ values: [_JSHandle]) -> JSObject {
        let list = JSObject.global.Array.function!.new()
        for (index, value) in values.enumerated() { list[index] = value }
        return list
    }

    // MARK: Reading values

    static func kind(_ value: _JSHandle) -> _JSKind { _JSKind(rawValue: helper("kind")(value).string ?? "object") ?? .object }
    static func text(_ value: _JSHandle) -> String? {
        if case .value(let text) = outcome(helper("text")(value)) { return text.string }
        return nil
    }
    static func number(_ value: _JSHandle) -> Double { helper("number")(value).number ?? .nan }
    static func int32(_ value: _JSHandle) -> Int32 { Int32(truncatingIfNeeded: Int64(helper("int32")(value).number ?? 0)) }
    static func uint32(_ value: _JSHandle) -> UInt32 { UInt32(truncatingIfNeeded: Int64(helper("uint32")(value).number ?? 0)) }
    static func truth(_ value: _JSHandle) -> Bool { helper("truth")(value).boolean ?? false }
    static func same(_ a: _JSHandle, _ b: _JSHandle) -> Bool { helper("same")(a, b).boolean ?? false }
    static func loose(_ a: _JSHandle, _ b: _JSHandle) -> Bool { helper("loose")(a, b).boolean ?? false }
    static func instance(_ value: _JSHandle, of constructor: _JSHandle) -> Bool { helper("instance")(value, constructor).boolean ?? false }
    static func keys(_ object: _JSHandle) -> [String] {
        guard let list = helper("keys")(object).object, let count = list.length.number else { return [] }
        return (0..<Int(count)).compactMap { list[$0].string }
    }
    /// The value's `length` when it is a number, else -1.
    static func length(_ object: _JSHandle) -> Int { Int(helper("length")(object).number ?? -1) }

    // MARK: Making values in a realm

    static func object(in global: JSObject) -> _JSHandle { helper("object")(global) }
    static func array(in global: JSObject) -> _JSHandle { helper("array")(global) }
    static func date(_ milliseconds: Double, in global: JSObject) -> _JSHandle { helper("date")(global, milliseconds) }
    static func error(_ message: String, in global: JSObject) -> _JSHandle { helper("error")(global, message) }
    static func symbol(_ description: String, in global: JSObject) -> _JSHandle { helper("symbol")(global, description) }
    static func regexp(_ pattern: String, _ flags: String, in global: JSObject) -> Outcome { outcome(helper("regexp")(global, pattern, flags)) }
    static func resolved(_ value: _JSHandle, in global: JSObject) -> _JSHandle { helper("resolved")(global, value) }
    static func rejected(_ value: _JSHandle, in global: JSObject) -> _JSHandle { helper("rejected")(global, value) }

    // MARK: Swift values that have no JavaScript form

    /// The Swift values handed to script as opaque objects, by their number (kept for the page's
    /// life, as a wrapper object may be held by script anywhere).
    nonisolated(unsafe) private static var wrapped: [Int: Any] = [:]
    nonisolated(unsafe) private static var nextWrapper = 0

    static func wrap(_ value: Any, in global: JSObject) -> _JSHandle {
        if let object = value as AnyObject?, type(of: value) is AnyClass {
            for (id, held) in wrapped where (held as AnyObject) === object { return helper("wrap")(global, id) }
        }
        nextWrapper += 1
        wrapped[nextWrapper] = value
        return helper("wrap")(global, nextWrapper)
    }

    /// The Swift value an opaque object stands for.
    static func unwrap(_ value: _JSHandle) -> Any? {
        let id = Int(helper("wrapped")(value).number ?? -1)
        return id < 0 ? nil : wrapped[id]
    }

    static func string(_ value: String) -> _JSHandle { .string(JSString(value)) }
}
#endif
