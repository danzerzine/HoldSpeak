import XCTest
@testable import HoldSpeakCore

final class TextCleanerTests: XCTestCase {
    func test_removesExtendedRussianHesitations_keepsShortFillers() {
        // Only extended hesitations (эээ, эммм) are dropped; "ну" is legitimate speech.
        XCTAssertEqual(TextCleaner.clean("ну эээ я пошел"), "Ну я пошел.")
    }
    func test_removesExtendedEnglishHesitations_keepsShortFillers() {
        // "uhm" matches the uhm+ rule; bare "uh" is kept (uh{2,} requires uhh…).
        XCTAssertEqual(TextCleaner.clean("uhm I think uh we should go"), "I think uh we should go.")
    }
    func test_collapsesStutter() {
        XCTAssertEqual(TextCleaner.clean("я я я думаю"), "Я думаю.")
    }
    func test_preservesMixedEnglishTokens() {
        let out = TextCleaner.clean("у нас созвон в zoom с product manager")
        XCTAssertTrue(out.contains("zoom"))
        XCTAssertTrue(out.contains("product manager"))
    }
    func test_normalizesWhitespaceAndPunctuation() {
        XCTAssertEqual(TextCleaner.clean("   привет    мир"), "Привет мир.")
    }
    func test_preservesExistingPunctuation() {
        XCTAssertEqual(TextCleaner.clean("это вопрос?"), "Это вопрос?")
    }
    func test_returnsEmptyForWhitespaceOnly() {
        XCTAssertEqual(TextCleaner.clean("   "), "")
    }
    func test_keepsLikeAsRegularWord() {
        XCTAssertEqual(TextCleaner.clean("I like pizza"), "I like pizza.")
    }

    // MARK: - Terminology canonicalization

    private var dict: [TerminologyEntry] {
        [
            TerminologyEntry(canonical: "pull request",
                             variants: ["пулл реквест", "пул-реквест", "пулреквест"]),
            TerminologyEntry(canonical: "code review",
                             variants: ["код ревью"]),
            TerminologyEntry(canonical: "Swift",
                             variants: ["свифт"],
                             caseSensitive: false),
        ]
    }

    func test_terminologyReplacesVariant() {
        let out = TextCleaner.clean("запушь пулл реквест в main", terminology: dict)
        XCTAssertEqual(out, "Запушь pull request в main.")
    }

    func test_terminologyReplacesHyphenatedVariant() {
        let out = TextCleaner.clean("сделай пул-реквест", terminology: dict)
        XCTAssertEqual(out, "Сделай pull request.")
    }

    func test_terminologyWordBoundary_shouldNotMatchInsideWord() {
        // Variant "пулреквест" should not match inside "пулреквестер"
        let out = TextCleaner.clean("позови пулреквестера", terminology: dict)
        XCTAssertFalse(out.lowercased().contains("pull request"))
    }

    func test_terminologyCaseInsensitiveByDefault() {
        let out = TextCleaner.clean("пиши на Свифт", terminology: dict)
        XCTAssertTrue(out.contains("Swift"))
    }

    func test_hallucinationBlacklist_stillWorks() {
        XCTAssertEqual(TextCleaner.clean("спасибо за просмотр"), "")
    }

    func test_hallucination_dropsWholeUtteranceIgnoringCaseAndPunctuation() {
        XCTAssertEqual(TextCleaner.clean("Спасибо за просмотр!"), "")
        XCTAssertEqual(TextCleaner.clean("  Thank you for watching...  "), "")
        XCTAssertEqual(TextCleaner.clean("Продолжение следует..."), "")
    }

    func test_hallucination_dropsBareYouFromNoise() {
        XCTAssertEqual(TextCleaner.clean("you", terminology: [], autoPunctuation: true, autoCapitalize: true), "")
        XCTAssertEqual(TextCleaner.clean("You.", terminology: [], autoPunctuation: true, autoCapitalize: true), "")
        XCTAssertNotEqual(TextCleaner.clean("you know", terminology: [], autoPunctuation: true, autoCapitalize: true), "")
    }

    func test_hallucination_dropsBareThanksFromSilence() {
        XCTAssertEqual(TextCleaner.clean("Thank you."), "")
        XCTAssertEqual(TextCleaner.clean("thank you"), "")
        XCTAssertEqual(TextCleaner.clean("Спасибо."), "")
    }

    func test_hallucination_dropsSubtitleCredits() {
        XCTAssertEqual(TextCleaner.clean("Субтитры сделал DimaTorzok"), "")
        XCTAssertEqual(TextCleaner.clean("Редактор субтитров А.Семкин"), "")
    }

    func test_hallucination_keepsPhraseInsideRealSpeech() {
        XCTAssertEqual(TextCleaner.clean("спасибо за внимание, коллеги"), "Спасибо за внимание, коллеги.")
        XCTAssertEqual(TextCleaner.clean("I want to subscribe to the newsletter"),
                       "I want to subscribe to the newsletter.")
        XCTAssertEqual(TextCleaner.clean("thank you for the review"), "Thank you for the review.")
        XCTAssertEqual(TextCleaner.clean("скажи ему спасибо"), "Скажи ему спасибо.")
    }

    func test_hallucinationFilterCanBeDisabled() {
        XCTAssertEqual(TextCleaner.clean("Спасибо."), "")
        XCTAssertEqual(TextCleaner.clean("Спасибо.", dropHallucinations: false), "Спасибо.")
    }
    func test_geminiPunctuationNotDoubled() {
        XCTAssertEqual(TextCleaner.clean("Готово.", dropHallucinations: false), "Готово.")
        XCTAssertEqual(TextCleaner.clean("Готово.", autoPunctuation: false, dropHallucinations: false), "Готово")
    }

    // MARK: - Repeats and brackets must not eat real speech (review 04.10)

    func test_keepsPrepositionBeforeWordWithSameStart() {
        XCTAssertEqual(TextCleaner.clean("Я сейчас в вагоне"), "Я сейчас в вагоне.")
        XCTAssertEqual(TextCleaner.clean("Взял с собой зонт"), "Взял с собой зонт.")
        XCTAssertEqual(TextCleaner.clean("We agreed on one thing"), "We agreed on one thing.")
    }

    func test_keepsRepeatedDigits() {
        XCTAssertEqual(TextCleaner.clean("Звони 8 800 555 35 35"), "Звони 8 800 555 35 35.")
        XCTAssertEqual(TextCleaner.clean("Встреча в 5 50"), "Встреча в 5 50.")
    }

    func test_keepsDoubledWordAsSpeech() {
        XCTAssertEqual(TextCleaner.clean("Он сказал да да"), "Он сказал да да.")
        XCTAssertEqual(TextCleaner.clean("very very good"), "Very very good.")
    }

    func test_collapsesRepeatedPhraseLoop() {
        XCTAssertEqual(TextCleaner.clean("открой файл открой файл открой файл"), "Открой файл.")
    }

    func test_keepsDictatedParentheses() {
        XCTAssertEqual(TextCleaner.clean("Встреча в среду (если получится) в офисе"),
                       "Встреча в среду (если получится) в офисе.")
        XCTAssertEqual(TextCleaner.clean("Встреча в среду (если получится) в офисе", dropHallucinations: false),
                       "Встреча в среду (если получится) в офисе.")
    }

    func test_dropsWhisperSoundAnnotations() {
        XCTAssertEqual(TextCleaner.clean("[музыка] привет"), "Привет.")
        XCTAssertEqual(TextCleaner.clean("(applause) thanks everyone"), "Thanks everyone.")
        XCTAssertEqual(TextCleaner.clean("[Music]"), "")
        XCTAssertEqual(TextCleaner.clean("[BLANK_AUDIO]"), "")
    }
}
