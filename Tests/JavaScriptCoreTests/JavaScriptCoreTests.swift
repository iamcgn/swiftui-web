// JavaScriptCore over the page's engine. Under Node (the wasm tests) the contexts run real
// script: evaluation and its completion value, globals a script declares, a library object's
// methods called as Highlightr and HighlightSwift call highlight.js, values converted both ways,
// exceptions reaching the handler, properties, constructors and comparisons. Natively there is
// no engine, and making a context gives nil, as the libraries' `guard let` expects of a failure.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import JavaScriptCore
import Testing

#if os(WASI)
@Suite(.serialized) struct JavaScriptCoreTests {
    @Test func scriptsRunAndDeclareGlobals() throws {
        let context = try #require(JSContext())
        #expect(context.evaluateScript("1 + 2").toInt32() == 3)
        context.evaluateScript("var swiftuiWebLibrary = (function () { return { twice: function (x) { return x * 2; }, name: 'lib' }; })();")
        let library = try #require(context.objectForKeyedSubscript("swiftuiWebLibrary"))
        #expect(library.isObject)
        #expect(library.objectForKeyedSubscript("name").toString() == "lib")
        #expect(library.invokeMethod("twice", withArguments: [21]).toDouble() == 42)
        #expect(context.globalObject.hasProperty("swiftuiWebLibrary"))
        #expect(context.objectForKeyedSubscript("swiftuiWebMissing").isUndefined)
    }

    /// What Highlightr and HighlightSwift do with highlight.js: a library object whose methods
    /// take a string and an options dictionary and give an object of results.
    @Test func aLibraryAnswersLikeHighlightJS() throws {
        let context = try #require(JSContext())
        context.evaluateScript("""
        var swiftuiWebHL = {
          highlight: function (code, options) {
            if (options.language !== 'swift') return undefined;
            return { value: '<span class="hljs-keyword">' + code + '</span>', language: options.language,
                     relevance: 7, illegal: !!options.ignoreIllegals };
          },
          highlightAuto: function (code) { return { value: code, language: 'plaintext', relevance: 0, illegal: false }; }
        };
        """)
        let hljs = try #require(context.objectForKeyedSubscript("swiftuiWebHL"))
        let result = try #require(hljs.invokeMethod("highlight", withArguments: ["let", ["language": "swift", "ignoreIllegals": true] as [String: Any]]))
        #expect(result.objectForKeyedSubscript("value").toString() == "<span class=\"hljs-keyword\">let</span>")
        #expect(result.objectForKeyedSubscript("language").toString() == "swift")
        #expect(result.objectForKeyedSubscript("relevance").toInt32() == 7)
        #expect(result.objectForKeyedSubscript("illegal").toBool())
        #expect(hljs.invokeMethod("highlight", withArguments: ["x", ["language": "rust"]]).isUndefined)
        #expect(hljs.invokeMethod("highlightAuto", withArguments: ["x"]).objectForKeyedSubscript("language").toString() == "plaintext")
    }

    @Test func valuesConvertBothWays() throws {
        let context = try #require(JSContext())
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let value = try #require(JSValue(object: ["n": 1.5, "s": "text", "b": true, "list": [1, "two", NSNull()] as [Any], "when": date] as [String: Any], in: context))
        #expect(value.isObject)
        #expect(value.objectForKeyedSubscript("list").isArray)
        #expect(value.objectForKeyedSubscript("when").isDate)
        let back = try #require(value.toDictionary())
        #expect(back["n"] as? Double == 1.5)
        #expect(back["s"] as? String == "text")
        #expect(back["b"] as? Bool == true)
        let list = try #require(back["list"] as? [Any])
        #expect(list.count == 3)
        #expect(list[0] as? Double == 1)
        #expect(list[1] as? String == "two")
        #expect(list[2] is NSNull)
        #expect((back["when"] as? Date) == date)

        #expect(JSValue(bool: false, in: context).isBoolean)
        #expect(JSValue(int32: -4, in: context).toInt32() == -4)
        #expect(JSValue(double: 4_294_967_297, in: context).toUInt32() == 1)
        #expect(JSValue(nullIn: context).isNull)
        #expect(JSValue(nullIn: context).toObject() is NSNull)
        #expect(JSValue(undefinedIn: context).toObject() == nil)
        #expect(context.evaluateScript("'12' * 2").toDouble() == 24)
        #expect(context.evaluateScript("[3, 4]").toArray().count == 2)
        #expect(context.evaluateScript("({ length: 2, 0: 'a', 1: 'b' })").toArray().map { $0 as? String } == ["a", "b"])
        #expect(context.evaluateScript("new Date(86400000)").toDate() == Date(timeIntervalSince1970: 86_400))
        #expect(context.evaluateScript("Symbol('tag')").toString() == "Symbol(tag)")
        #expect(context.evaluateScript("null").toString() == "null")
    }

    /// A Swift value with no script form travels as an opaque object and comes back as itself.
    @Test func swiftObjectsComeBackAsThemselves() throws {
        final class Token: @unchecked Sendable {}
        let context = try #require(JSContext())
        let token = Token()
        context.setObject(token, forKeyedSubscript: "swiftuiWebToken")
        context.evaluateScript("var swiftuiWebHeld = [swiftuiWebToken];")
        let held = try #require(context.objectForKeyedSubscript("swiftuiWebHeld").toArray())
        #expect((held.first as? Token) === token)
        #expect(context.objectForKeyedSubscript("swiftuiWebToken").toObjectOf(Token.self) as? Token === token)
    }

    @Test func exceptionsReachTheHandler() throws {
        let context = try #require(JSContext())
        let result = context.evaluateScript("throw new TypeError('bad thing')")
        #expect(result?.isUndefined == true)
        #expect(context.exception.objectForKeyedSubscript("message").toString() == "bad thing")
        #expect(context.exception.toString() == "TypeError: bad thing")

        final class Seen { var list: [String] = [] }
        let box = Seen()
        context.exceptionHandler = { _, exception in box.list.append(exception?.toString() ?? "") }
        context.exception = nil
        context.evaluateScript("(function () { return missing.value; })()")
        _ = context.evaluateScript("({ get boom() { throw new Error('getter'); } })").objectForKeyedSubscript("boom")
        _ = JSValue(newRegularExpressionFromPattern: "(", flags: "", in: context)
        let seen = box.list
        #expect(seen.count == 3)
        #expect(seen.first?.hasPrefix("ReferenceError") == true)
        #expect(seen.count > 1 && seen[1] == "Error: getter")
        #expect(seen.count > 2 && seen[2].hasPrefix("SyntaxError"))
        #expect(context.exception == nil)
    }

    @Test func propertiesConstructorsAndComparisons() throws {
        let context = try #require(JSContext())
        let object = try #require(JSValue(newObjectIn: context))
        object.setValue(3, forProperty: "count")
        object.setObject("x", forKeyedSubscript: 7)
        #expect(object.forProperty("count").toInt32() == 3)
        #expect(object.objectForKeyedSubscript("7").toString() == "x")
        #expect(object.deleteProperty("count"))
        #expect(!object.hasProperty("count"))
        object.defineProperty("fixed", descriptor: [JSPropertyDescriptorValueKey: 9, JSPropertyDescriptorWritableKey: false])
        object.setValue(10, forProperty: "fixed")
        #expect(object.forProperty("fixed").toInt32() == 9)
        #expect(Set(object.toDictionary().keys.compactMap { $0 as? String }) == ["7"])

        let array = try #require(JSValue(newArrayIn: context))
        array.setValue("first", at: 0)
        array.setObject("second", atIndexedSubscript: 1)
        #expect(array.forProperty("length").toInt32() == 2)
        #expect(array.atIndex(1).toString() == "second")

        let point = try #require(context.evaluateScript("(function Point(x) { this.x = x; })"))
        let made = try #require(point.construct(withArguments: [5]))
        #expect(made.forProperty("x").toInt32() == 5)
        #expect(made.isInstance(of: point))
        #expect(point.call(withArguments: [1]).isUndefined)

        let error = try #require(JSValue(newErrorFromMessage: "oops", in: context))
        #expect(error.forProperty("message").toString() == "oops")
        #expect(JSValue(newSymbolFromDescription: "s", in: context).isSymbol)
        #expect(context.evaluateScript("2").isEqual(to: 2))
        #expect(!context.evaluateScript("'2'").isEqual(to: 2))
        #expect(context.evaluateScript("'2'").isEqualWithTypeCoercion(to: 2))
        #expect(JSValue(newPromiseResolvedWithResult: 1, in: context).isObject)
        #expect(context.evaluateScript("1", withSourceURL: URL(string: "https://example.com/a.js")).toInt32() == 1)
    }
}
#else
@Suite struct JavaScriptCoreTests {
    @Test func withoutAnEngineNoContextIsMade() {
        #expect(JSContext() == nil)
        #expect(JSContext(virtualMachine: JSVirtualMachine()) == nil)
        #expect(JSValue(object: "x", in: nil) == nil)
        #expect(JSValue(newObjectIn: nil) == nil)
        #expect(JSPropertyDescriptorValueKey == "value")
    }
}
#endif
