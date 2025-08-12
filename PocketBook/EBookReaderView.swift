//
//  EBookReaderView.swift
//  PocketBook
//
//  Created by Armağan Başkan on 11.08.2025.
//


//
//  EBookReaderView.swift
//  PocketBook
//
//  Created by Armağan Başkan on 11.08.2025.
//

import SwiftUI
import SwiftData
import PDFKit

struct EBookReaderView: View {
    @ObservedObject var book: Book
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var processedBook: ProcessedBook?
    @State private var currentParagraphIndex = 0
    @State private var isLoading = true
    @State private var showingSettings = false
    @State private var fontSize: Double = 18
    @State private var lineSpacing: Double = 1.4
    @State private var isDarkMode = false
    
    var body: some View {
        ZStack {
            // Arka plan rengi
            (isDarkMode ? Color.black : Color.white)
                .ignoresSafeArea()
            
            if isLoading {
                VStack {
                    ProgressView("Kitap hazırlanıyor...")
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Metin çıkarılıyor ve formatlanıyor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            } else if let book = processedBook {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(Array(book.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                                Text(paragraph)
                                    .font(.system(size: fontSize))
                                    .lineSpacing(lineSpacing)
                                    .foregroundColor(isDarkMode ? .white : .black)
                                    .id(index)
                                    .onAppear {
                                        // Okunan paragrafı kaydet
                                        updateReadingProgress(paragraphIndex: index)
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 40)
                    }
                    .onAppear {
                        // Son okunan yere git
                        if book.paragraphs.indices.contains(currentParagraphIndex) {
                            proxy.scrollTo(currentParagraphIndex, anchor: .top)
                        }
                    }
                }
            } else {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Kitap yüklenemedi")
                        .font(.headline)
                    Text("Lütfen tekrar deneyin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "textformat")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView(
                fontSize: $fontSize,
                lineSpacing: $lineSpacing,
                isDarkMode: $isDarkMode
            )
        }
        .task {
            await loadBookText()
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
    
    private func loadBookText() async {
        isLoading = true
        
        do {
            // E-kitap dosyasından metni yükle
            if let bookData = try loadEBookData() {
                await MainActor.run {
                    processedBook = ProcessedBook(
                        pages: bookData.pages.map { PageText(pageNumber: $0.pageNumber, text: $0.text, originalImage: UIImage()) },
                        paragraphs: bookData.paragraphs,
                        fullText: bookData.fullText
                    )
                    currentParagraphIndex = book.lastReadPage
                    isLoading = false
                }
            } else {
                // PDF'den görüntüleri al ve OCR yap
                let images = try await loadImagesFromPDF()
                let pageTexts = try await TextExtractionService.extractText(from: images)
                let processed = TextExtractionService.processText(pageTexts)
                
                await MainActor.run {
                    processedBook = processed
                    isLoading = false
                }
            }
        } catch {
            print("Kitap yükleme hatası: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func loadEBookData() throws -> EBookData? {
        let ebookURL = try FileStorage.ebookURL(for: book.id)
        
        guard FileManager.default.fileExists(atPath: ebookURL.path) else {
            return nil
        }
        
        let data = try Data(contentsOf: ebookURL)
        let decoder = JSONDecoder()
        return try decoder.decode(EBookData.self, from: data)
    }
    
    private func loadImagesFromPDF() async throws -> [UIImage] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let pdfURL = try FileStorage.pdfURL(for: book.id)
                    guard let pdfDocument = PDFDocument(url: pdfURL) else {
                        continuation.resume(throwing: TextExtractionError.imageProcessingFailed)
                        return
                    }
                    
                    var images: [UIImage] = []
                    
                    for i in 0..<pdfDocument.pageCount {
                        if let page = pdfDocument.page(at: i) {
                            let pageSize = page.bounds(for: .mediaBox)
                            let renderer = UIGraphicsImageRenderer(size: pageSize.size)
                            
                            let image = renderer.image { context in
                                context.cgContext.setFillColor(UIColor.white.cgColor)
                                context.cgContext.fill(pageSize)
                                
                                context.cgContext.translateBy(x: 0, y: pageSize.size.height)
                                context.cgContext.scaleBy(x: 1.0, y: -1.0)
                                
                                page.draw(with: .mediaBox, to: context.cgContext)
                            }
                            
                            images.append(image)
                        }
                    }
                    
                    continuation.resume(returning: images)
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func updateReadingProgress(paragraphIndex: Int) {
        currentParagraphIndex = paragraphIndex
        
        // SwiftData'ya kaydet
        Task { @MainActor in
            book.lastReadPage = paragraphIndex
            book.updatedAt = Date()
            try? modelContext.save()
        }
    }
}

struct ReaderSettingsView: View {
    @Binding var fontSize: Double
    @Binding var lineSpacing: Double
    @Binding var isDarkMode: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Metin Boyutu") {
                    HStack {
                        Text("A").font(.system(size: 14))
                        Slider(value: $fontSize, in: 12...32, step: 1)
                        Text("A").font(.system(size: 20))
                    }
                    Text("Boyut: \(Int(fontSize))pt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Satır Aralığı") {
                    Slider(value: $lineSpacing, in: 1.0...2.0, step: 0.1)
                    Text("Aralık: \(String(format: "%.1f", lineSpacing))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Görünüm") {
                    Toggle("Gece Modu", isOn: $isDarkMode)
                }
                
                Section("Örnek Metin") {
                    Text("Bu örnek bir metindir. Ayarlarınızın nasıl göründüğünü burada görebilirsiniz.")
                        .font(.system(size: fontSize))
                        .lineSpacing(lineSpacing)
                }
            }
            .navigationTitle("Okuma Ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// E-kitap veri yapıları
struct EBookData: Codable {
    let title: String
    let author: String?
    let pages: [EBookPage]
    let paragraphs: [String]
    let fullText: String
}

struct EBookPage: Codable {
    let pageNumber: Int
    let text: String
}

enum BookError: Error {
    case pdfCreationFailed
    case fileStorageError
    case ocrFailed
}