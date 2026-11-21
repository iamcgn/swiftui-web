// The language recognizer (Sources/NaturalLanguage) on a sentence in each script it tells apart
// and in the Latin-script languages it scores by common words, the way IceCubes tags a post
// (the first hypothesis, kept at 0.85 or more) and Mlem picks what to translate from.
import Testing
import NaturalLanguage

private func top(_ text: String) -> (String, Double)? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first else { return nil }
    return (language.rawValue, confidence)
}

@Suite struct NaturalLanguageTests {
    @Test func latinSentencesReachConfidence() {
        let sentences: [(String, String)] = [
            ("en", "The quick brown fox jumps over the lazy dog and the cat is happy"),
            ("fr", "Je pense que c'est une très bonne idée pour le projet de la semaine"),
            ("de", "Ich glaube, dass das eine sehr gute Idee für das Projekt ist"),
            ("it", "Questa è una bella giornata e non vedo l'ora di andare al mare con gli amici"),
            ("pt", "Eu acho que isso é uma boa ideia para o projeto da semana"),
            ("nl", "Ik denk dat het een goed idee is voor het project van de week"),
            ("sv", "Jag tror att det är en bra idé för projektet"),
            ("pl", "Myślę, że to jest bardzo dobry pomysł na ten projekt"),
            ("tr", "Bugün hava çok güzel ve ben de dışarı çıkmak istiyorum"),
            ("vi", "Tôi nghĩ rằng đây là một ý tưởng tốt cho dự án"),
            ("id", "Saya pikir ini adalah ide yang bagus untuk proyek kita"),
            ("es", "Hola, ¿cómo estás? Me gusta mucho la comida de este lugar porque es muy buena"),
        ]
        for (expected, sentence) in sentences {
            let result = top(sentence)
            #expect(result?.0 == expected, "\(sentence)")
            #expect((result?.1 ?? 0) >= 0.85, "\(sentence)")
        }
    }

    @Test func scriptsPickTheirLanguage() {
        let sentences: [(NLLanguage, String)] = [
            (.japanese, "今日はいい天気ですね"),
            (.simplifiedChinese, "我们今天去学校"),
            (.traditionalChinese, "我們今天去學校"),
            (.korean, "안녕하세요, 만나서 반갑습니다"),
            (.russian, "Привет, как дела? Это хороший день."),
            (.ukrainian, "Привіт, як справи? Сьогодні гарний день."),
            (.arabic, "مرحبا كيف حالك"),
            (.persian, "سلام، حال شما چطور است؟"),
            (.hebrew, "שלום, מה שלומך?"),
            (.greek, "Καλημέρα, τι κάνεις;"),
            (.thai, "สวัสดีครับ วันนี้อากาศดี"),
            (.hindi, "नमस्ते, आप कैसे हैं?"),
            (.georgian, "გამარჯობა"),
        ]
        for (expected, sentence) in sentences {
            #expect(NLLanguageRecognizer.dominantLanguage(for: sentence) == expected, "\(sentence)")
            let hypotheses = NLLanguageRecognizer().with(sentence).languageHypotheses(withMaximum: 3)
            #expect(hypotheses[expected] == 1, "\(sentence)")
        }
    }

    @Test func mixedScriptsSplitTheHypotheses() {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString("Привет")
        recognizer.processString("γεια σου")
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        #expect(hypotheses.count == 2)
        #expect(abs((hypotheses[.russian] ?? 0) - 6.0 / 13.0) < 1e-9)
        #expect(abs((hypotheses[.greek] ?? 0) - 7.0 / 13.0) < 1e-9)
        #expect(recognizer.dominantLanguage == .greek)
        #expect(recognizer.languageHypotheses(withMaximum: 1).count == 1)
        #expect(recognizer.languageHypotheses(withMaximum: 0).isEmpty)
    }

    @Test func nothingToTellByIsNil() {
        #expect(NLLanguageRecognizer.dominantLanguage(for: "") == nil)
        #expect(NLLanguageRecognizer.dominantLanguage(for: "1234 !? 🎉") == nil)
        let recognizer = NLLanguageRecognizer()
        #expect(recognizer.languageHypotheses(withMaximum: 3).isEmpty)
        recognizer.processString("Das ist gut")
        #expect(recognizer.dominantLanguage == .german)
        recognizer.reset()
        #expect(recognizer.dominantLanguage == nil)
    }

    @Test func constraintsAndHints() {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString("Ich glaube, dass das eine sehr gute Idee für das Projekt ist")
        recognizer.languageConstraints = [.english, .french]
        #expect(recognizer.dominantLanguage != .german)
        recognizer.languageConstraints = [.japanese]
        #expect(recognizer.dominantLanguage == nil)
        recognizer.languageConstraints = []
        #expect(recognizer.dominantLanguage == .german)

        // Danish and Norwegian share their common words: a hint settles it.
        let nordic = NLLanguageRecognizer()
        nordic.processString("det er ikke")
        nordic.languageHints = [.norwegian: 0.9, .danish: 0.1]
        #expect(nordic.dominantLanguage == .norwegian)
        nordic.languageHints = [.danish: 0.9]
        #expect(nordic.dominantLanguage == .danish)
    }

    @Test func languageValues() {
        #expect(NLLanguage.english.rawValue == "en")
        #expect(NLLanguage("zh-Hans") == .simplifiedChinese)
        #expect(NLLanguage(rawValue: "nb") == .norwegian)
        #expect(NLLanguage.undetermined.rawValue == "und")
    }
}

private extension NLLanguageRecognizer {
    func with(_ text: String) -> NLLanguageRecognizer {
        processString(text)
        return self
    }
}
