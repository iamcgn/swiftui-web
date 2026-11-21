// Natural Language on the web: `NLLanguage` and `NLLanguageRecognizer`, which apps use to tag a
// post or a message with its language (IceCubes before it posts, Mlem before it translates).
// Apple's recognizer is a trained model; this one is small and deterministic. Letters in a script
// that only one language here writes (Hangul, Greek, Thai, Hebrew and so on) count for that
// language. Han counts as Japanese beside kana, and otherwise as Chinese, simplified or
// traditional by the characters that differ. Cyrillic and Arabic letters that only some of their
// languages use pick among them. Latin text is scored by the common words and letters of 21
// languages. Each script's share of the letters is split among its languages, so mixed text
// gets mixed hypotheses. Apple's framework re-exports Foundation: a file importing only this
// module names `String` APIs from it.
@_exported import WebFoundation

/// A language, as its BCP 47 code.
public struct NLLanguage: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let undetermined = NLLanguage("und")
    public static let amharic = NLLanguage("am")
    public static let arabic = NLLanguage("ar")
    public static let armenian = NLLanguage("hy")
    public static let bengali = NLLanguage("bn")
    public static let bulgarian = NLLanguage("bg")
    public static let burmese = NLLanguage("my")
    public static let catalan = NLLanguage("ca")
    public static let cherokee = NLLanguage("chr")
    public static let croatian = NLLanguage("hr")
    public static let czech = NLLanguage("cs")
    public static let danish = NLLanguage("da")
    public static let dutch = NLLanguage("nl")
    public static let english = NLLanguage("en")
    public static let finnish = NLLanguage("fi")
    public static let french = NLLanguage("fr")
    public static let georgian = NLLanguage("ka")
    public static let german = NLLanguage("de")
    public static let greek = NLLanguage("el")
    public static let gujarati = NLLanguage("gu")
    public static let hebrew = NLLanguage("he")
    public static let hindi = NLLanguage("hi")
    public static let hungarian = NLLanguage("hu")
    public static let icelandic = NLLanguage("is")
    public static let indonesian = NLLanguage("id")
    public static let italian = NLLanguage("it")
    public static let japanese = NLLanguage("ja")
    public static let kannada = NLLanguage("kn")
    public static let kazakh = NLLanguage("kk")
    public static let khmer = NLLanguage("km")
    public static let korean = NLLanguage("ko")
    public static let lao = NLLanguage("lo")
    public static let malay = NLLanguage("ms")
    public static let malayalam = NLLanguage("ml")
    public static let marathi = NLLanguage("mr")
    public static let mongolian = NLLanguage("mn")
    public static let norwegian = NLLanguage("nb")
    public static let oriya = NLLanguage("or")
    public static let persian = NLLanguage("fa")
    public static let polish = NLLanguage("pl")
    public static let portuguese = NLLanguage("pt")
    public static let punjabi = NLLanguage("pa")
    public static let romanian = NLLanguage("ro")
    public static let russian = NLLanguage("ru")
    public static let simplifiedChinese = NLLanguage("zh-Hans")
    public static let sinhalese = NLLanguage("si")
    public static let slovak = NLLanguage("sk")
    public static let spanish = NLLanguage("es")
    public static let swedish = NLLanguage("sv")
    public static let tamil = NLLanguage("ta")
    public static let telugu = NLLanguage("te")
    public static let thai = NLLanguage("th")
    public static let tibetan = NLLanguage("bo")
    public static let traditionalChinese = NLLanguage("zh-Hant")
    public static let turkish = NLLanguage("tr")
    public static let ukrainian = NLLanguage("uk")
    public static let urdu = NLLanguage("ur")
    public static let vietnamese = NLLanguage("vi")
    public static let kurdish = NLLanguage("ku")
}

/// Finds the language a text is most likely written in.
open class NLLanguageRecognizer: @unchecked Sendable {
    private var text = ""

    /// Prior probabilities for languages the text may be in.
    open var languageHints: [NLLanguage: Double] = [:]
    /// When not empty, the only languages the recognizer considers.
    open var languageConstraints: [NLLanguage] = []

    public init() {}

    /// The most likely language of the string, or nil when it has no letters to tell by.
    open class func dominantLanguage(for string: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(string)
        return recognizer.dominantLanguage
    }

    /// Adds the string to the text the recognizer judges.
    open func processString(_ string: String) {
        if !text.isEmpty { text.append(" ") }
        text.append(string)
    }

    /// Forgets the text processed so far; hints and constraints stay.
    open func reset() { text = "" }

    /// The most likely language of the text processed so far, or nil when it has no letters to tell by.
    open var dominantLanguage: NLLanguage? { ranked().first?.language }

    /// Up to `maxHypotheses` languages, each with its probability.
    open func languageHypotheses(withMaximum maxHypotheses: Int) -> [NLLanguage: Double] {
        var result: [NLLanguage: Double] = [:]
        for entry in ranked().prefix(max(0, maxHypotheses)) { result[entry.language] = entry.probability }
        return result
    }

    private func ranked() -> [(language: NLLanguage, probability: Double)] {
        var scores = _LanguageGuess.scores(for: text)
        if !languageConstraints.isEmpty {
            let allowed = Set(languageConstraints)
            scores = scores.filter { allowed.contains($0.key) }
        }
        if !languageHints.isEmpty {
            for (language, score) in scores { scores[language] = score * (1 + 4 * max(0, languageHints[language] ?? 0)) }
        }
        let total = scores.values.reduce(0, +)
        guard total > 0 else { return [] }
        return scores.map { (language: $0.key, probability: $0.value / total) }.sorted {
            $0.probability != $1.probability ? $0.probability > $1.probability
                : _LanguageGuess.order($0.language) < _LanguageGuess.order($1.language)
        }
    }
}

/// The recognizer's rules: letters counted by script, and Latin text scored by common words.
enum _LanguageGuess {
    enum Script: Hashable {
        case latin, han, kana, hangul, cyrillic, greek, arabic, hebrew, thai, devanagari, bengali, gurmukhi,
             gujarati, oriya, tamil, telugu, kannada, malayalam, sinhala, lao, tibetan, myanmar, georgian,
             armenian, ethiopic, khmer, mongolian, cherokee
    }

    static func script(of scalar: Unicode.Scalar) -> Script? {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF: return .latin
        case 0x3040...0x30FF, 0x31F0...0x31FF: return .kana
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return .han
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return .hangul
        case 0x0400...0x04FF, 0x0500...0x052F: return .cyrillic
        case 0x0370...0x03FF, 0x1F00...0x1FFF: return .greek
        case 0x0600...0x06FF, 0x0750...0x077F, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return .arabic
        case 0x0590...0x05FF: return .hebrew
        case 0x0E00...0x0E7F: return .thai
        case 0x0900...0x097F: return .devanagari
        case 0x0980...0x09FF: return .bengali
        case 0x0A00...0x0A7F: return .gurmukhi
        case 0x0A80...0x0AFF: return .gujarati
        case 0x0B00...0x0B7F: return .oriya
        case 0x0B80...0x0BFF: return .tamil
        case 0x0C00...0x0C7F: return .telugu
        case 0x0C80...0x0CFF: return .kannada
        case 0x0D00...0x0D7F: return .malayalam
        case 0x0D80...0x0DFF: return .sinhala
        case 0x0E80...0x0EFF: return .lao
        case 0x0F00...0x0FFF: return .tibetan
        case 0x1000...0x109F: return .myanmar
        case 0x10A0...0x10FF: return .georgian
        case 0x0530...0x058F: return .armenian
        case 0x1200...0x139F: return .ethiopic
        case 0x13A0...0x13FF: return .cherokee
        case 0x1780...0x17FF: return .khmer
        case 0x1800...0x18AF: return .mongolian
        default: return nil
        }
    }

    /// The scripts only one language here writes.
    static let single: [Script: NLLanguage] = [
        .hangul: .korean, .greek: .greek, .hebrew: .hebrew, .thai: .thai, .bengali: .bengali, .gurmukhi: .punjabi,
        .gujarati: .gujarati, .oriya: .oriya, .tamil: .tamil, .telugu: .telugu, .kannada: .kannada,
        .malayalam: .malayalam, .sinhala: .sinhalese, .lao: .lao, .tibetan: .tibetan, .myanmar: .burmese,
        .georgian: .georgian, .armenian: .armenian, .ethiopic: .amharic, .khmer: .khmer, .mongolian: .mongolian,
        .cherokee: .cherokee,
    ]

    /// The unnormalised score of each language for the text. Only letters count: punctuation such
    /// as the Arabic comma sits in its script's block.
    static func scores(for text: String) -> [NLLanguage: Double] {
        var counts: [Script: Int] = [:]
        var letters: [Unicode.Scalar: Int] = [:]
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            guard let script = script(of: scalar) else { continue }
            counts[script, default: 0] += 1
            if script != .latin { letters[scalar, default: 0] += 1 }
        }
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [:] }
        var scores: [NLLanguage: Double] = [:]
        func add(_ share: Int, _ split: [NLLanguage: Double]) {
            let sum = split.values.reduce(0, +)
            guard sum > 0 else { return }
            for (language, weight) in split { scores[language, default: 0] += Double(share) / Double(total) * weight / sum }
        }
        func has(_ characters: String) -> Int {
            var found = 0
            for scalar in characters.unicodeScalars { found += letters[scalar] ?? 0 }
            return found
        }
        for (script, count) in counts {
            switch script {
            case .latin: add(count, latin(text))
            case .kana: add(count, [.japanese: 1])
            case .han:
                if counts[.kana] != nil { add(count, [.japanese: 1]); break }
                let simplified = has("这们说国会对来时个为学发么过后还没经实话见长东车开门问间书")
                let traditional = has("這們說國會對來時個為學發麼過後還沒經實話見長東車開門問間書")
                add(count, simplified >= traditional ? [.simplifiedChinese: 1] : [.traditionalChinese: 1])
            case .cyrillic:
                if has("ҚқҒғҢңӘәҰұҺһ") > 0 { add(count, [.kazakh: 1]) }
                else if has("ІіЇїЄєҐґ") > 0 { add(count, [.ukrainian: 1]) }
                else if has("ӨөҮү") > 0 { add(count, [.mongolian: 1]) }
                else if has("ЫыЭэЁё") > 0 { add(count, [.russian: 1]) }
                else if has("Ъъ") > 0 { add(count, [.bulgarian: 1]) }
                else { add(count, russianOrBulgarian(text)) }
            case .arabic:
                if has("ٹڈڑںےۓہھ") > 0 { add(count, [.urdu: 1]) }
                else if has("پچژگکی") > 0 { add(count, [.persian: 1]) }
                else { add(count, [.arabic: 1]) }
            case .devanagari: add(count, has("ळ") > 0 ? [.marathi: 1] : [.hindi: 1])
            default: if let language = single[script] { add(count, [language: 1]) }
            }
        }
        return scores
    }

    /// Cyrillic text with neither language's own letters (#308): Russian and Bulgarian told apart
    /// by the common words only one of them uses (each weighted by the cube of its count when both
    /// have some), and split nearly evenly when none is found, so a caller with a confidence
    /// threshold leaves the language unset.
    static func russianOrBulgarian(_ text: String) -> [NLLanguage: Double] {
        let russian: Set<String> = ["что", "это", "он", "она", "оно", "они", "его", "её", "ее", "в", "я", "вы", "мы", "ты", "очень",
                                    "сегодня", "есть", "был", "была", "было", "были", "так", "все", "всё", "только", "уже", "где", "когда",
                                    "если", "или", "меня", "тебя", "нет", "здравствуйте", "привет", "спасибо", "хорошо", "день"]
        let bulgarian: Set<String> = ["е", "че", "ще", "това", "са", "от", "се", "сте", "сме", "съм", "си", "днес", "тя", "той",
                                      "ние", "вие", "аз", "където", "кога", "ако", "само", "вече", "няма", "здравейте",
                                      "здрасти", "благодаря", "добре", "ден", "хубав", "хубаво"]
        var ru = 0.0, bg = 0.0
        var word = ""
        func count() {
            guard !word.isEmpty else { return }
            let inRussian = russian.contains(word), inBulgarian = bulgarian.contains(word)
            if inRussian && !inBulgarian { ru += 1 } else if inBulgarian && !inRussian { bg += 1 }
            word = ""
        }
        for character in text.lowercased() {
            if character.isLetter { word.append(character) } else { count() }
        }
        count()
        if bg == 0 { return ru == 0 ? [.russian: 0.55, .bulgarian: 0.45] : [.russian: 1] }
        if ru == 0 { return [.bulgarian: 1] }
        return [.russian: ru * ru * ru, .bulgarian: bg * bg * bg]
    }

    /// Latin text's languages, each weighted by the cube of its common words and letters found,
    /// so that the language with the most evidence stands out.
    static func latin(_ text: String) -> [NLLanguage: Double] {
        var words: [String] = []
        var word = ""
        var marks: [Character: Int] = [:]
        for character in text.lowercased() {
            if !character.isASCII { marks[character, default: 0] += 1 }
            if character.isLetter {
                word.append(character)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        var result: [NLLanguage: Double] = [:]
        for (language, list) in commonWords {
            var score = 0.0
            for word in words where list.contains(word) { score += 1 }
            if let letters = distinctive[language] {
                var found = 0
                for character in letters { found += marks[character] ?? 0 }
                score += 0.5 * Double(min(found, words.count))
            }
            if score > 0 { result[language] = score * score * score }
        }
        return result
    }

    /// Which of two equally likely languages comes first: the most written ones lead.
    static func order(_ language: NLLanguage) -> Int {
        for (index, candidate) in preference.enumerated() where candidate == language { return index }
        return preference.count
    }

    static let preference: [NLLanguage] = [.english, .spanish, .french, .german, .portuguese, .italian, .dutch, .indonesian,
                                           .turkish, .polish, .vietnamese, .swedish, .romanian, .czech, .hungarian,
                                           .danish, .norwegian, .finnish, .catalan, .croatian, .slovak]

    static let commonWords: [NLLanguage: Set<String>] = {
        let lists: [(NLLanguage, String)] = [
            (.english, "the and of to in is that it for you was with on as are be this have not but they at by from or his her we an will can all there their what so if about which when would one who just been has more do my your our me out up"),
            (.spanish, "el la de que y en los las del se por con para una un es no lo al como más pero sus le ya o este sí porque esta entre cuando muy sin sobre también me hasta hay donde quien desde nos durante"),
            (.french, "le la les de des et est un une du en que qui dans pour pas au aux sur avec ce cette il elle ne se sont par plus nous vous mais ou je sa son ses leur été être très"),
            (.german, "der die das und ist nicht ein eine zu den von mit sich des auf für im dem es auch als an wie wir ich sie er aus bei nach noch oder nur über sind wird werden hat haben"),
            (.italian, "il la di che e è un una per non in del della dei gli le si con sono lo da al ma come anche più nel alla questo questa ho hai mi ti ci sul degli delle"),
            (.portuguese, "o a os as de que e do da dos das em um uma para com não por se mais na no como mas foi ao ele ela seu sua é são também já está muito isso quando eu você"),
            (.dutch, "de het een en van in is dat op te zijn met voor niet die aan er maar ook als bij nog wel om dan of hij zij we ik je wordt worden naar uit over"),
            (.swedish, "och att det som en på är av för med till den har de inte om ett var jag men så vi kan sig från eller också nu skulle hade över efter"),
            (.danish, "og at det i en til er som på de med af for ikke den har jeg et var men vi kan sig fra eller også nu skulle havde efter være"),
            (.norwegian, "og i det som en på er av for med til den har de ikke om et var jeg men så vi kan seg fra eller også nå skulle hadde etter være"),
            (.finnish, "ja on ei se että oli hän mutta kun niin tai joka ovat myös sen kuin mitä minä sinä tämä ole olen jo vain kaikki"),
            (.polish, "i w nie się na to że z do jest jak po co tak za od ale o już jego jej są czy przez tylko też może jestem był była być bardzo"),
            (.czech, "a v se na je že to s z do jsem jako ale o by pro jsou jeho její tak už když také nebo jak byl byla být velmi ještě"),
            (.slovak, "a v sa na je že to s z do som ako ale o by pre sú jeho jej tak už keď aj alebo bol bola byť veľmi ešte"),
            (.hungarian, "a az és hogy nem is egy van meg de el ez azt csak már mint volt még ki sem vagy lesz minden nagyon itt ott"),
            (.romanian, "și în de la a cu nu se pe că din este o un mai care sunt pentru ce fost sau dar au ne foarte acest această"),
            (.turkish, "ve bir bu da de için ile ne çok daha olarak gibi ama en mi değil var ben sen o biz siz onlar şey kadar sonra"),
            (.croatian, "i je u se na da za su od ne s što kao ali o koji to iz bi sam smo ste biti bio bila jer samo"),
            (.catalan, "el la i de que a en els les del es un una per amb no és al com però més ho hi aquest aquesta són també"),
            (.indonesian, "dan yang di ini itu dengan untuk tidak ada dari ke akan saya kami kita mereka juga pada atau sudah bisa lebih karena"),
            (.vietnamese, "và của là có không được cho một những này người trong đã với các để thì khi như tôi bạn chúng"),
        ]
        var table: [NLLanguage: Set<String>] = [:]
        for (language, words) in lists { table[language] = Set(words.split(separator: " ").map(String.init)) }
        return table
    }()

    /// Letters that point to a language among those written in Latin script.
    static let distinctive: [NLLanguage: [Character]] = [
        .spanish: Array("ñ¿¡"), .portuguese: Array("ãõ"), .french: Array("èêœàù"), .german: Array("ßäöü"),
        .polish: Array("łąęśżźćń"), .czech: Array("řěů"), .slovak: Array("ľĺŕô"), .romanian: Array("șțăâî"),
        .hungarian: Array("őű"), .turkish: Array("ğşı"), .icelandic: Array("þð"), .danish: Array("æø"),
        .norwegian: Array("æø"), .swedish: Array("åäö"), .finnish: Array("äö"), .croatian: Array("čćđšž"),
        .catalan: Array("ŀç"),
        .vietnamese: Array("ơưđạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹ"),
    ]
}
