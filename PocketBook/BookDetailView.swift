//
//  BookDetailView.swift
//  PocketBook
//
//  Created by Armağan Başkan on 10.08.2025.
//

import SwiftUI
import SwiftData
import PDFKit

struct BookDetailView: View {
    @ObservedObject var book: Book
    @Environment(\.modelContext) private var modelContext

    @State private var showingScanner = false
    @State private var isBusy = false
    @State private var showReader = false
    @State private var pageCount: Int = 0
    @State private var fileSize: String = ""
    @State private var hasFile: Bool = false
    @State private var isEBookFormat: Bool = false // YENİ

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Cover Image
                if let data = book.coverImageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                }
                
                // Book Info
                VStack(spacing: 8) {
                    Text(book.title)
                        .font(.title)
                        .multilineTextAlignment(.center)
                    
                    if let author = book.author {
                        Text(author)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Eklendi: \(book.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if book.updatedAt != book.createdAt {
                        Text("Güncellendi: \(book.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Book Status Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Kitap Durumu")
                        .font(.headline)
                    
                    if hasFile {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(isEBookFormat ? "E-kitap Hazır" : "PDF Hazır")
                            Spacer()
                        }
                        
                        if pageCount > 0 {
                            HStack {
                                Image(systemName: isEBookFormat ? "doc.text" : "doc.richtext")
                                Text(isEBookFormat ? "\(pageCount) paragraf" : "\(pageCount) sayfa")
                                Spacer()
                            }
                        }
                        
                        if !fileSize.isEmpty {
                            HStack {
                                Image(systemName: "internaldrive")
                                Text(fileSize)
                                Spacer()
                            }
                        }
                        
                        if book.lastReadPage > 0 {
                            HStack {
                                Image(systemName: "bookmark.fill")
                                Text(isEBookFormat ? "Son okunan: Paragraf \(book.lastReadPage + 1)" : "Son okunan: Sayfa \(book.lastReadPage + 1)")
                                Spacer()
                            }
                            
                            if pageCount > 0 {
                                let progress = Double(book.lastReadPage + 1) / Double(pageCount)
                                ProgressView(value: progress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                Text("\(Int(progress * 100))% tamamlandı")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                            Text("Henüz sayfa taranmadı")
                            Spacer()
                        }
                        
                        Text("Bu kitaba içerik eklemek için 'Sayfa Tara' butonunu kullanın")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: { showingScanner = true }) {
                        HStack {
                            if isBusy {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: hasFile ? "doc.text.viewfinder" : "plus.circle.fill")
                            }
                            Text(hasFile ? "Daha Fazla Sayfa Ekle" : "Sayfa Tara")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isBusy)
                    
                    if hasFile {
                        // YENİ: E-kitap formatına göre doğru okuyucuyu aç
                        if isEBookFormat {
                            NavigationLink {
                                EBookReaderView(book: book)
                            } label: {
                                HStack {
                                    Image(systemName: "book.open")
                                    Text(book.lastReadPage > 0 ? "Okumaya Devam Et" : "Okumaya Başla")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        } else {
                            NavigationLink {
                                ReaderContainerView(book: book)
                            } label: {
                                HStack {
                                    Image(systemName: "book.open")
                                    Text(book.lastReadPage > 0 ? "Okumaya Devam Et" : "Okumaya Başla")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                    } else {
                        Button(action: {}) {
                            HStack {
                                Image(systemName: "book.open")
                                Text("Kitabı Oku")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.3))
                            .foregroundColor(.gray)
                            .cornerRadius(8)
                        }
                        .disabled(true)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding()
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadBookInfo()
        }
        .sheet(isPresented: $showingScanner) {
            DocumentScannerView { images in
                Task {
                    await savePages(images: images)
                }
            }
        }
    }
    
    private func loadBookInfo() {
        // Check if book file exists and determine format
        hasFile = FileStorage.bookFileExists(for: book.id)
        isEBookFormat = FileStorage.isEBook(for: book.id)
        
        // Get file size
        if let size = FileStorage.bookFileSize(for: book.id) {
            fileSize = formatFileSize(size)
        } else {
            fileSize = ""
        }
        
        // Get page/paragraph count
        if hasFile {
            if isEBookFormat {
                loadParagraphCount()
            } else {
                loadPageCount()
            }
        } else {
            pageCount = 0
        }
    }
    
    // YENİ: E-kitap için paragraf sayısını yükle
    private func loadParagraphCount() {
        Task {
            do {
                let ebookURL = try FileStorage.ebookURL(for: book.id)
                let data = try Data(contentsOf: ebookURL)
                let decoder = JSONDecoder()
                let bookData = try decoder.decode(EBookData.self, from: data)
                
                await MainActor.run {
                    pageCount = bookData.paragraphs.count
                }
            } catch {
                await MainActor.run {
                    pageCount = 0
                }
            }
        }
    }
    
    private func loadPageCount() {
        Task {
            do {
                let pdfURL = try FileStorage.pdfURL(for: book.id)
                guard let pdfDocument = PDFDocument(url: pdfURL) else {
                    await MainActor.run {
                        pageCount = 0
                    }
                    return
                }
                
                await MainActor.run {
                    pageCount = pdfDocument.pageCount
                }
            } catch {
                await MainActor.run {
                    pageCount = 0
                }
            }
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func savePages(images: [UIImage]) async {
        guard !images.isEmpty else { return }
        
        await MainActor.run {
            isBusy = true
        }
        
        do {
            if isEBookFormat {
                // E-kitap formatına yeni sayfalar ekle
                try await appendToEBook(images: images)
            } else {
                // PDF'e yeni sayfalar ekle
                let pdfURL = try FileStorage.pdfURL(for: book.id)
                try PDFService.append(images: images, toPDFAt: pdfURL)
            }
            
            await MainActor.run {
                book.updatedAt = Date()
                try? modelContext.save()
                
                // Refresh book info
                loadBookInfo()
                isBusy = false
            }
        } catch {
            print("PDF save failed:", error)
            await MainActor.run {
                isBusy = false
            }
        }
    }
    
    // YENİ: E-kitaba yeni sayfalar ekle
    private func appendToEBook(images: [UIImage]) async throws {
        // Mevcut e-kitap verisini yükle
        let ebookURL = try FileStorage.ebookURL(for: book.id)
        let existingData = try Data(contentsOf: ebookURL)
        let decoder = JSONDecoder()
        var bookData = try decoder.decode(EBookData.self, from: existingData)
        
        // Yeni sayfaları OCR ile işle
        let newPageTexts = try await TextExtractionService.extractText(from: images)
        
        // Mevcut verilere ekle
        let startPageNumber = bookData.pages.count + 1
        let newPages = newPageTexts.enumerated().map { index, pageText in
            EBookPage(pageNumber: startPageNumber + index, text: pageText.text)
        }
        
        bookData = EBookData(
            title: bookData.title,
            author: bookData.author,
            pages: bookData.pages + newPages,
            paragraphs: bookData.paragraphs + TextExtractionService.processText(newPageTexts).paragraphs,
            fullText: bookData.fullText + "\n\n" + newPageTexts.map { $0.text }.joined(separator: "\n\n")
        )
        
        // Güncellenmiş veriyi kaydet
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(bookData)
        try jsonData.write(to: ebookURL)
    }
}
