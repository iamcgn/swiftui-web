// The browser behind `NSRegularExpression` (decision 0021, the Ember app): the pattern is a
// JavaScript `RegExp` with the `d` flag, so every match reports the UTF-16 indices of the
// whole and of each group — the units `NSRange` counts. A pattern the engine rejects compiles
// to nil (the initializer throws); a search runs `matchAll` over the string's range.
#if os(WASI)
import JavaScriptKit
import WebFoundation

@MainActor
enum RegexHost {
    private static let compile: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        return try? make.throws.new("pattern", "flags", "try { return new RegExp(pattern, flags + 'd'); } catch (e) { return null; }")
    }()

    /// `(regex, string, location, length)` → a flat array: per match the group count, then
    /// each group's start and end (-1 for a group that did not take part).
    private static let search: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        let body = """
        var out = [];
        var slice = string.substring(location, location + length);
        regex.lastIndex = 0;
        for (var m of slice.matchAll(regex)) {
          var groups = m.length;
          out.push(groups);
          for (var g = 0; g < groups; g++) {
            var pair = m.indices[g];
            if (pair) { out.push(location + pair[0], location + pair[1]); } else { out.push(-1, -1); }
          }
        }
        return out;
        """
        return try? make.throws.new("regex", "string", "location", "length", body)
    }()

    static func install() {
        _RegexHost.compile = { pattern, flags in
            guard let compile, let regex = compile(pattern, flags).object else { return nil }
            return regex
        }
        _RegexHost.matches = { handle, string, location, length in
            guard let search, let regex = handle as? JSObject, let flat = search(regex, string, location, length).object,
                  let count = flat.length.number.map({ Int($0) }) else { return [] }
            var matches: [_RegexHost.Match] = []
            var index = 0
            while index < count {
                let groups = Int(flat[index].number ?? 0)
                index += 1
                var ranges: [NSRange] = []
                for _ in 0..<groups {
                    let start = Int(flat[index].number ?? -1), end = Int(flat[index + 1].number ?? -1)
                    index += 2
                    ranges.append(start < 0 ? .notFound : NSRange(location: start, length: end - start))
                }
                matches.append(_RegexHost.Match(ranges: ranges))
            }
            return matches
        }
    }
}
#endif
