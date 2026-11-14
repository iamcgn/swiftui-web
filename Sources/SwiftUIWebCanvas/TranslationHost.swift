// The browser behind Translation: Chrome's on-device `Translator` (a pair's model downloads once,
// then translates offline) and `LanguageDetector`. One translator per pair is kept for the page's
// life. A browser without them (Safari, Firefox) answers every pair as unavailable.
#if os(WASI)
import JavaScriptKit
import TranslationHost

@MainActor
enum TranslationHost {
    /// The page's translator functions: `{ availability, prepare, translate, detect }`, each
    /// taking its arguments and a `done` callback.
    private static let api: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        let body = """
        var has = typeof Translator !== 'undefined';
        var pairs = {};
        var detector = null;
        var name = function (e) { return (e && e.name) || 'UnknownError'; };
        var make = function (s, t) {
          var key = s + '>' + t;
          if (!pairs[key]) {
            pairs[key] = Translator.create({ sourceLanguage: s, targetLanguage: t });
            pairs[key].catch(function () { delete pairs[key]; });
          }
          return pairs[key];
        };
        return {
          availability: function (s, t, done) {
            if (!has) { done('unavailable'); return; }
            Translator.availability({ sourceLanguage: s, targetLanguage: t })
              .then(function (a) { done(a === 'available' ? 'available' : (a === 'unavailable' ? 'unavailable' : 'downloadable')); },
                    function () { done('unavailable'); });
          },
          prepare: function (s, t, done) {
            if (!has) { done('NotSupportedError'); return; }
            make(s, t).then(function () { done(null); }, function (e) { done(name(e)); });
          },
          translate: function (s, t, text, done) {
            if (!has) { done(null, 'NotSupportedError'); return; }
            make(s, t).then(function (tr) { return tr.translate(text); })
              .then(function (r) { done(r, null); }, function (e) { done(null, name(e)); });
          },
          detect: function (text, done) {
            if (typeof LanguageDetector === 'undefined') { done(null); return; }
            if (!detector) { detector = LanguageDetector.create(); detector.catch(function () { detector = null; }); }
            detector.then(function (d) { return d.detect(text); }).then(function (r) {
              var best = r && r.length ? r[0] : null;
              done(best && best.detectedLanguage !== 'und' ? best.detectedLanguage : null);
            }, function () { done(null); });
          }
        };
        """
        guard let factory = try? make.throws.new(body) else { return nil }
        return factory().object
    }()

    static func install() {
        guard let api else { return }
        _TranslationHost.availability = { source, target, done in
            let callback = JSOneshotClosure { (arguments: [JSValue]) -> JSValue in
                switch arguments.first?.string {
                case "available": done(.available)
                case "downloadable": done(.downloadable)
                default: done(.unavailable)
                }
                return .undefined
            }
            _ = api.availability!(source, target, callback)
        }
        _TranslationHost.prepare = { source, target, done in
            let callback = JSOneshotClosure { (arguments: [JSValue]) -> JSValue in
                done(arguments.first?.string)
                return .undefined
            }
            _ = api.prepare!(source, target, callback)
        }
        _TranslationHost.translate = { source, target, text, done in
            let callback = JSOneshotClosure { (arguments: [JSValue]) -> JSValue in
                done(arguments.first?.string, arguments.count > 1 ? arguments[1].string : nil)
                return .undefined
            }
            _ = api.translate!(source, target, text, callback)
        }
        _TranslationHost.detect = { text, done in
            let callback = JSOneshotClosure { (arguments: [JSValue]) -> JSValue in
                done(arguments.first?.string)
                return .undefined
            }
            _ = api.detect!(text, callback)
        }
    }
}
#endif
