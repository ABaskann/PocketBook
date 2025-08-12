//
//  AddBookView.swift
//  PocketBook
//
//  Created by Armağan Başkan on 10.08.2025.
//

import SwiftUI
import SwiftData

struct AddBookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var author = ""
    @State private var coverImage: UIImage?
    @State private var scannedImages: [UIImage] = []
    @State private var showingPicker = false
    @State private var showingScanner = false
    @State private var isProcessing = false
    @State private var useEBookFormat = true // Yeni seçenek

    var body: some View {
        NavigationStack {
            Form {
                Section("Kitap Bilgisi") {
                    TextField("Başlık", text: $title)
                    TextField("Yazar", text: $author)
                }
                
                Section("İçerik") {
                    Button("Sayfa Tara") {
                        showingScanner = true
                    }
                    
                    if !scannedImages.isEmpty {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.green)
                            Text("\(scannedImages.count) sayfa tarandı")
                                .foregroundColor(.green)
                        }
                    }
                    
                    Toggle("E-kitap formatında kaydet", isOn: $useEBookFormat)
                    
                    if useEBookFormat {
                        Text("OCR ile metin çıkarılıp e-kitap formatında kaydedilir")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("PDF formatında kaydedilir")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Kapak") {
                    if let img = coverImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 180)
                            .cornerRadius(8)
                    }
                    
                    HStack {
                        Button("Kapak Resmi Seç") {
                            showingPicker = true
                        }
                        
                        if !scannedImages.isEmpty {
                            Button("İlk Sayfayı Kapak Yap") {
                                coverImage = scannedImages.first
                            }
                        }
                    }
                }
                
                if isProcessing {
                    Section {
                        HStack {
                            ProgressView()
                            if useEBookFormat {
                                Text("Metin çıkarılıyor ve kitap kaydediliyor...")
                            } else {
                                Text("PDF oluşturuluyor ve kitap kaydediliyor...")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kitap Ekle")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || scannedImages.isEmpty || isProcessing)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPicker) {
                ImagePicker(image: $coverImage)
            }
            .sheet(isPresented: $showingScanner) {
                DocumentScannerView { images in
                    print("Received \(images.count) scanned images")
                    handleScannedImages(images)
                }
            }
        }
    }
    
    private func handleScannedImages(_ images: [UIImage]) {
        print("Processing \(images.count) scanned images")
        scannedImages = images
        
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            title = "Taranan Belge \(Date().formatted(date: .numeric, time: .omitted))"
        }
        
        if coverImage == nil, let firstImage = images.first {
            coverImage = firstImage
        }
        
        print("Scanned images processed successfully")
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty, !scannedImages.isEmpty else {
            print("Cannot save: missing title or scanned pages")
            return
        }
        
        isProcessing = true
        
        Task {
            do {
                // Kitap oluştur
                let book = Book(
                    id: UUID(),
                    title: title.trimmingCharacters(in: .whitespaces),
                    author: author.isEmpty ? nil : author,
                    coverImageData: coverImage?.jpegData(compressionQuality: 0.8)
                )
                
                print("Created book: \(book.title) with ID: \(book.id)")
                
                if useEBookFormat {
                    // E-kitap formatında kaydet
                    try await saveAsEBook(book: book, images: scannedImages)
                } else {
                    // PDF formatında kaydet
                    try await saveAsPDF(book: book, images: scannedImages)
                }
                
                await MainActor.run {
                    modelContext.insert(book)
                    
                    do {
                        try modelContext.save()
                        print("Book saved to database successfully")
                        isProcessing = false
                        dismiss()
                    } catch {
                        print("Failed to save book to database: \(error)")
                        isProcessing = false
                    }
                }
                
            } catch {
                print("Failed to save book: \(error)")
                await MainActor.run {
                    isProcessing = false
                }
            }
        }
    }
    
    private func saveAsEBook(book: Book, images: [UIImage]) async throws {
        // OCR ile metin çıkar
        let pageTexts = try await TextExtractionService.extractText(from: images)
        let processedBook = TextExtractionService.processText(pageTexts)
        
        // JSON formatında kaydet
        let bookData = EBookData(
            title: book.title,
            author: book.author,
            pages: pageTexts.map { EBookPage(pageNumber: $0.pageNumber, text: $0.text) },
            paragraphs: processedBook.paragraphs,
            fullText: processedBook.fullText
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(bookData)
        
        // E-kitap dosyasını kaydet
        let ebookURL = try FileStorage.ebookURL(for: book.id)
        try jsonData.write(to: ebookURL)
        
        print("E-book saved to: \(ebookURL)")
    }
    
    private func saveAsPDF(book: Book, images: [UIImage]) async throws {
        let pdfData = try await createPDFFromImages(images)
        let fileURL = try FileStorage.saveBookFile(bookId: book.id, data: pdfData)
        print("PDF saved to: \(fileURL)")
    }
    
    private func createPDFFromImages(_ images: [UIImage]) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let pdfData = NSMutableData()
                
                guard let consumer = CGDataConsumer(data: pdfData) else {
                    continuation.resume(throwing: BookError.pdfCreationFailed)
                    return
                }
                
                var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
                
                guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                    continuation.resume(throwing: BookError.pdfCreationFailed)
                    return
                }
                
                for (index, image) in images.enumerated() {
                    print("Adding page \(index + 1) of \(images.count) to PDF")
                    
                    pdfContext.beginPDFPage(nil)
                    
                    let imageSize = image.size
                    let pageSize = mediaBox.size
                    
                    let widthRatio = pageSize.width / imageSize.width
                    let heightRatio = pageSize.height / imageSize.height
                    let ratio = min(widthRatio, heightRatio)
                    
                    let scaledWidth = imageSize.width * ratio
                    let scaledHeight = imageSize.height * ratio
                    
                    let x = (pageSize.width - scaledWidth) / 2
                    let y = (pageSize.height - scaledHeight) / 2
                    
                    let drawRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
                    
                    if let cgImage = image.cgImage {
                        pdfContext.draw(cgImage, in: drawRect)
                    }
                    
                    pdfContext.endPDFPage()
                }
                
                pdfContext.closePDF()
                
                print("PDF creation completed with \(pdfData.length) bytes")
                continuation.resume(returning: pdfData as Data)
            }
        }
    }
}
