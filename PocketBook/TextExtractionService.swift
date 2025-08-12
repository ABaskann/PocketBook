//
//  TextExtractionService.swift
//  PocketBook
//
//  Created by Armağan Başkan on 11.08.2025.
//

import Vision
import UIKit
import NaturalLanguage

struct TextExtractionService {
    
    enum DetectedLanguage {
        case turkish, english, spanish, french, german, italian, portuguese
        case russian, chinese, japanese, korean, arabic, unknown
        
        var visionLanguageCode: String {
            switch self {
            case .turkish: return "tr-TR"
            case .english: return "en-US"
            case .spanish: return "es-ES"
            case .french: return "fr-FR"
            case .german: return "de-DE"
            case .italian: return "it-IT"
            case .portuguese: return "pt-BR"
            case .russian: return "ru-RU"
            case .chinese: return "zh-CN"
            case .japanese: return "ja-JP"
            case .korean: return "ko-KR"
            case .arabic: return "ar-SA"
            case .unknown: return "en-US"
            }
        }
    }
    
    static func extractText(from images: [UIImage]) async throws -> [PageText] {
        var pages: [PageText] = []
        
        // İlk birkaç sayfadan dil algıla
        let detectedLanguage = await detectLanguage(from: Array(images.prefix(3)))
        
        for (index, image) in images.enumerated() {
            let text = try await extractTextFromImage(image, language: detectedLanguage)
            let cleanedText = cleanAndFormatText(text, language: detectedLanguage)
            
            pages.append(PageText(
                pageNumber: index + 1,
                text: cleanedText,
                originalImage: image
            ))
        }
        
        return pages
    }
    
    private static func detectLanguage(from images: [UIImage]) async -> DetectedLanguage {
        // Hızlı dil algılama için ilk birkaç sayfadan küçük örnekler al
        var sampleTexts: [String] = []
        
        for image in images {
            if let quickText = try? await extractTextFromImage(image, language: .english, isQuickScan: true) {
                sampleTexts.append(String(quickText.prefix(500)))
            }
        }
        
        let combinedSample = sampleTexts.joined(separator: " ")
        return analyzeLanguage(combinedSample)
    }
    
    private static func extractTextFromImage(_ image: UIImage, language: DetectedLanguage, isQuickScan: Bool = false) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw TextExtractionError.imageProcessingFailed
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let recognizedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                continuation.resume(returning: recognizedText)
            }
            
            // OCR ayarları
            request.recognitionLevel = isQuickScan ? .fast : .accurate
            request.usesLanguageCorrection = true
            
            // Dil spesifik ayarlar
            switch language {
            case .turkish:
                request.recognitionLanguages = ["tr-TR", "en-US"]
            case .spanish:
                request.recognitionLanguages = ["es-ES", "en-US"]
            case .french:
                request.recognitionLanguages = ["fr-FR", "en-US"]
            case .german:
                request.recognitionLanguages = ["de-DE", "en-US"]
            case .italian:
                request.recognitionLanguages = ["it-IT", "en-US"]
            case .portuguese:
                request.recognitionLanguages = ["pt-BR", "pt-PT", "en-US"]
            case .russian:
                request.recognitionLanguages = ["ru-RU", "en-US"]
            case .chinese:
                request.recognitionLanguages = ["zh-CN", "zh-TW"]
            case .japanese:
                request.recognitionLanguages = ["ja-JP", "en-US"]
            case .korean:
                request.recognitionLanguages = ["ko-KR", "en-US"]
            case .arabic:
                request.recognitionLanguages = ["ar-SA", "en-US"]
            case .english, .unknown:
                request.recognitionLanguages = ["en-US", "tr-TR"]
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Language Detection
    private static func analyzeLanguage(_ text: String) -> DetectedLanguage {
        let sampleText = String(text.prefix(1000))
        
        // NaturalLanguage framework ile dil algılama
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sampleText)
        
        if let dominantLanguage = recognizer.dominantLanguage {
            switch dominantLanguage.rawValue {
            case "tr": return .turkish
            case "en": return .english
            case "es": return .spanish
            case "fr": return .french
            case "de": return .german
            case "it": return .italian
            case "pt": return .portuguese
            case "ru": return .russian
            case "zh": return .chinese
            case "ja": return .japanese
            case "ko": return .korean
            case "ar": return .arabic
            default: break
            }
        }
        
        // Manuel karakter analizi (NaturalLanguage yetersiz kalırsa)
        return detectLanguageManually(sampleText)
    }
    
    private static func detectLanguageManually(_ text: String) -> DetectedLanguage {
        // CJK karakterleri kontrol et
        if text.range(of: "[\\u4e00-\\u9fff]", options: .regularExpression) != nil { return .chinese }
        if text.range(of: "[\\u3040-\\u309f\\u30a0-\\u30ff]", options: .regularExpression) != nil { return .japanese }
        if text.range(of: "[\\uac00-\\ud7af]", options: .regularExpression) != nil { return .korean }
        
        // Arapça ve Kiril
        if text.range(of: "[\\u0600-\\u06ff]", options: .regularExpression) != nil { return .arabic }
        if text.range(of: "[\\u0400-\\u04ff]", options: .regularExpression) != nil { return .russian }
        
        // Latin tabanlı diller için skorlama
        let scores = [
            (calculateLanguageScore(text, language: .turkish), DetectedLanguage.turkish),
            (calculateLanguageScore(text, language: .english), DetectedLanguage.english),
            (calculateLanguageScore(text, language: .spanish), DetectedLanguage.spanish),
            (calculateLanguageScore(text, language: .french), DetectedLanguage.french),
            (calculateLanguageScore(text, language: .german), DetectedLanguage.german),
            (calculateLanguageScore(text, language: .italian), DetectedLanguage.italian),
            (calculateLanguageScore(text, language: .portuguese), DetectedLanguage.portuguese)
        ]
        
        return scores.max { $0.0 < $1.0 }?.1 ?? .unknown
    }
    
    private static func calculateLanguageScore(_ text: String, language: DetectedLanguage) -> Double {
        let lowercased = text.lowercased()
        
        let patterns: [DetectedLanguage: (chars: String, words: [String])] = [
            .turkish: ("çğıöşüÇĞIİÖŞÜ", ["bir", "bu", "şu", "ve", "ile", "için", "ama", "fakat", "çünkü", "olan"]),
            .english: ("", ["the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by"]),
            .spanish: ("ñáéíóúüÑÁÉÍÓÚÜ", ["el", "la", "de", "que", "y", "a", "en", "un", "es", "se", "no", "te"]),
            .french: ("àâäçéèêëïîôöùûüÿñæœ", ["le", "de", "et", "à", "un", "il", "être", "en", "avoir", "que", "pour"]),
            .german: ("äöüßÄÖÜ", ["der", "die", "und", "in", "den", "von", "zu", "das", "mit", "sich", "des"]),
            .italian: ("àèéìíîòóùú", ["il", "di", "che", "e", "la", "per", "un", "in", "con", "da", "su"]),
            .portuguese: ("ãâáàçêéèíîóôõú", ["o", "de", "a", "e", "do", "da", "em", "um", "para", "é", "com", "não"])
        ]
        
        guard let pattern = patterns[language] else { return 0 }
        
        // Karakter skoru
        let specialChars = text.filter { pattern.chars.contains($0) }.count
        let totalChars = text.filter { $0.isLetter }.count
        let charScore = totalChars > 0 ? Double(specialChars) / Double(totalChars) * 10 : 0
        
        // Kelime skoru
        let words = lowercased.components(separatedBy: .whitespacesAndNewlines)
        let matchingWords = words.filter { pattern.words.contains($0) }.count
        let wordScore = words.count > 0 ? Double(matchingWords) / Double(words.count) * 5 : 0
        
        return charScore + wordScore
    }
    
    // MARK: - Text Cleaning and Formatting
    private static func cleanAndFormatText(_ rawText: String, language: DetectedLanguage) -> String {
        var text = rawText
        
        // Temel temizlik
        text = basicTextCleaning(text)
        
        // Dil spesifik OCR hata düzeltmeleri
        text = applyLanguageSpecificFixes(text, language: language)
        
        // Noktalama düzeltmeleri
        text = fixPunctuation(text, language: language)
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func basicTextCleaning(_ text: String) -> String {
        var cleaned = text
        
        // Çoklu boşlukları tek boşluğa çevir
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Gereksiz satır sonlarını temizle
        cleaned = cleaned.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        
        // Yaygın OCR hataları
        let commonFixes: [String: String] = [
            "rn": "m", "cl": "d", "vv": "w", "tl": "d", "fi": "fl",
            "0": "O", "1": "I", "5": "S", "8": "B", "6": "G"
        ]
        
        for (wrong, correct) in commonFixes {
            // Sadece kelime içindeyse değiştir
            cleaned = cleaned.replacingOccurrences(
                of: "\\b\(wrong)\\b",
                with: correct,
                options: .regularExpression
            )
        }
        
        return cleaned
    }
    
    private static func applyLanguageSpecificFixes(_ text: String, language: DetectedLanguage) -> String {
        var fixed = text
        
        switch language {
        case .turkish:
            let turkishFixes: [String: String] = [
                "c,": "ç", "C,": "Ç", "g~": "ğ", "G~": "Ğ",
                "i.": "ı", "I.": "İ", "o~": "ö", "O~": "Ö",
                "s,": "ş", "S,": "Ş", "u~": "ü", "U~": "Ü",
                "ii": "ü", "ıı": "ü", "aa": "â"
            ]
            for (wrong, correct) in turkishFixes {
                fixed = fixed.replacingOccurrences(of: wrong, with: correct)
            }
            
        case .spanish:
            let spanishFixes: [String: String] = [
                "n~": "ñ", "N~": "Ñ",
                "a'": "á", "e'": "é", "i'": "í", "o'": "ó", "u'": "ú",
                "A'": "Á", "E'": "É", "I'": "Í", "O'": "Ó", "U'": "Ú"
            ]
            for (wrong, correct) in spanishFixes {
                fixed = fixed.replacingOccurrences(of: wrong, with: correct)
            }
            
        case .french:
            let frenchFixes: [String: String] = [
                "a`": "à", "a^": "â", "e`": "è", "e'": "é", "e^": "ê",
                "i^": "î", "o^": "ô", "u`": "ù", "u^": "û", "c,": "ç"
            ]
            for (wrong, correct) in frenchFixes {
                fixed = fixed.replacingOccurrences(of: wrong, with: correct)
            }
            
        case .german:
            let germanFixes: [String: String] = [
                "a\"": "ä", "A\"": "Ä", "o\"": "ö", "O\"": "Ö",
                "u\"": "ü", "U\"": "Ü", "ss": "ß"
            ]
            for (wrong, correct) in germanFixes {
                fixed = fixed.replacingOccurrences(of: wrong, with: correct)
            }
            
        case .italian:
            let italianFixes: [String: String] = [
                "a`": "à", "e`": "è", "e'": "é", "i`": "ì", "i'": "í",
                "o`": "ò", "o'": "ó", "u`": "ù", "u'": "ú"
            ]
            for (wrong, correct) in italianFixes {
                fixed = fixed.replacingOccurrences(of: wrong, with: correct)
            }
            
        case .portuguese:
            let portugueseFixes: [String: String] = [
                "a~": "ã", "a^": "â", "a'": "á", "a`": "à",
                "e^": "ê", "e'": "é", "i'": "í", "o^": "ô",
                "o'": "ó", "o~": "õ", "u'": "ú", "c,": "ç"
            ]
            for (wrong, correct) in portugueseFixes {
                fixed = fixed.replacingOccurrences(of: wrong, with: correct)
            }
            
        case .russian:
            // Kiril-Latin karışımı düzeltmeleri
            let cyrillicFixes: [String: String] = [
                "P": "Р", "p": "р", "H": "Н", "h": "н",
                "B": "В", "b": "в", "C": "С", "c": "с"
            ]
            for (wrong, correct) in cyrillicFixes {
                fixed = fixed.replacingOccurrences(of: wrong, with: correct)
            }
            
        case .chinese, .japanese, .korean:
            // CJK karakterler arası gereksiz boşlukları kaldır
            fixed = fixed.replacingOccurrences(
                of: "([\\u4e00-\\u9fff\\u3040-\\u309f\\u30a0-\\u30ff\\uac00-\\ud7af])\\s+([\\u4e00-\\u9fff\\u3040-\\u309f\\u30a0-\\u30ff\\uac00-\\ud7af])",
                with: "$1$2",
                options: .regularExpression
            )
            
        default:
            break
        }
        
        return fixed
    }
    
    private static func fixPunctuation(_ text: String, language: DetectedLanguage) -> String {
        var fixed = text
        
        // Noktalama öncesi gereksiz boşlukları kaldır
        fixed = fixed.replacingOccurrences(
            of: "\\s+([.,!?;:])",
            with: "$1",
            options: .regularExpression
        )
        
        // Noktalama sonrası boşluk ekle (CJK dilleri hariç)
        if ![.chinese, .japanese, .korean].contains(language) {
            fixed = fixed.replacingOccurrences(
                of: "([.,!?;:])([a-zA-ZçğıöşüÇĞIİÖŞÜáéíóúàèìòùâêîôûäëïöüñ])",
                with: "$1 $2",
                options: .regularExpression
            )
        }
        
        // Tırnak işaretlerini düzelt
//        switch language {
//              case .french:
//                  fixed = fixed.replacingOccurrences(of: "\"([^\"]*?)\"", with: "« $1 »", options: .regularExpression)
//              case .german:
//                  fixed = fixed.replacingOccurrences(of: "\"([^\"]*?)\"", with: "„$1"", options: .regularExpression)
//              default:
//                  fixed = fixed.replacingOccurrences(of: "\"([^\"]*?)\"", with: ""$1"", options: .regularExpression)
//              }
              
              return fixed
          }
    
    // MARK: - Text Processing
    static func processText(_ pageTexts: [PageText]) -> ProcessedBook {
        let fullText = pageTexts.map { $0.text }.joined(separator: "\n\n")
        
        // Dil algıla
        let language = analyzeLanguage(fullText)
        
        // Paragrafları ayır ve temizle
        let paragraphs = splitIntoParagraphs(fullText, language: language)
        
        return ProcessedBook(
            pages: pageTexts,
            paragraphs: paragraphs,
            fullText: fullText
        )
    }
    
    private static func splitIntoParagraphs(_ text: String, language: DetectedLanguage) -> [String] {
        var paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // Çok kısa paragrafları birleştir
        var mergedParagraphs: [String] = []
        var currentParagraph = ""
        
        let minLength = getMinParagraphLength(for: language)
        
        for paragraph in paragraphs {
            if paragraph.count < minLength && !currentParagraph.isEmpty {
                currentParagraph += " " + paragraph
            } else {
                if !currentParagraph.isEmpty {
                    mergedParagraphs.append(formatParagraph(currentParagraph, language: language))
                }
                currentParagraph = paragraph
            }
        }
        
        if !currentParagraph.isEmpty {
            mergedParagraphs.append(formatParagraph(currentParagraph, language: language))
        }
        
        return mergedParagraphs
    }
    
    private static func getMinParagraphLength(for language: DetectedLanguage) -> Int {
        switch language {
        case .chinese, .japanese, .korean: return 20
        case .arabic: return 30
        default: return 50
        }
    }
    
    private static func formatParagraph(_ paragraph: String, language: DetectedLanguage) -> String {
        var formatted = paragraph
        
        // Başındaki gereksiz karakterleri temizle
        formatted = formatted.replacingOccurrences(
            of: "^[\\s\\-_=*]+",
            with: "",
            options: .regularExpression
        )
        
        // CJK ve Arapça dilleri için özel formatlamaatürk
        if [.chinese, .japanese, .korean, .arabic].contains(language) {
            return formatted
        }
        
        // Latin tabanlı diller için standart formatlamaölö
        if !formatted.isEmpty {
            formatted = formatted.prefix(1).uppercased() + formatted.dropFirst()
        }
        
        // Son noktalama kontrol et
        if !formatted.hasSuffix(".") && !formatted.hasSuffix("!") && !formatted.hasSuffix("?") {
            formatted += "."
        }
        
        return formatted
    }
}

struct PageText {
    let pageNumber: Int
    let text: String
    let originalImage: UIImage
}

struct ProcessedBook {
    let pages: [PageText]
    let paragraphs: [String]
    let fullText: String
}

enum TextExtractionError: Error {
    case imageProcessingFailed
    case ocrFailed
}
