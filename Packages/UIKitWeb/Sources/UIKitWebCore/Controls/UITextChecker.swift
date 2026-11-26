// UITextChecker: spelling checks and word completions. The page has no dictionary, so no word
// is misspelled and there are no guesses or completions; words the app teaches or ignores are
// kept, as UIKit keeps them.
import WebFoundation

open class UITextChecker: UIObjectBase {
    nonisolated(unsafe) private static var learnedWords: Set<String> = []

    /// Words this checker ignores.
    open var ignoredWords: [String]?

    /// The range of the first misspelled word: none (`NSNotFound`), as there's no dictionary.
    open func rangeOfMisspelledWord(in stringToCheck: String, range: NSRange, startingAt startingOffset: Int, wrap wrapFlag: Bool,
                                    language: String) -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    /// Spellings for a word: none.
    open func guesses(forWordRange range: NSRange, in string: String, language: String) -> [String]? { [] }

    /// Words that complete a partial word: none.
    open func completions(forPartialWordRange range: NSRange, in string: String, language: String) -> [String]? { [] }

    open func ignoreWord(_ wordToIgnore: String) {
        ignoredWords = (ignoredWords ?? []) + [wordToIgnore]
    }

    open class func learnWord(_ word: String) { learnedWords.insert(word) }
    open class func hasLearnedWord(_ word: String) -> Bool { learnedWords.contains(word) }
    open class func unlearnWord(_ word: String) { learnedWords.remove(word) }

    /// The languages the checker knows: none here.
    open class var availableLanguages: [String] { [] }
}
