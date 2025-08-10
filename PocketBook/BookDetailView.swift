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
                    
                    Text("Added: \(book.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if book.updatedAt != book.createdAt {
                        Text("Updated: \(book.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Book Status Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Book Status")
                        .font(.headline)
                    
                    if hasFile {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("PDF Available")
                            Spacer()
                        }
                        
                        if pageCount > 0 {
                            HStack {
                                Image(systemName: "doc.text")
                                Text("\(pageCount) pages")
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
                                Text("Last read: Page \(book.lastReadPage + 1)")
                                Spacer()
                            }
                            
                            if pageCount > 0 {
                                let progress = Double(book.lastReadPage + 1) / Double(pageCount)
                                ProgressView(value: progress)
                                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                Text("\(Int(progress * 100))% completed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                            Text("No pages scanned yet")
                            Spacer()
                        }
                        
                        Text("Use 'Scan Pages' to add content to this book")
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
                            Text(hasFile ? "Add More Pages" : "Scan Pages")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(isBusy)
                    
                    if hasFile {
                        NavigationLink {
                            ReaderContainerView(book: book)
                        } label: {
                            HStack {
                                Image(systemName: "book.open")
                                Text(book.lastReadPage > 0 ? "Continue Reading" : "Start Reading")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    } else {
                        Button(action: {}) {
                            HStack {
                                Image(systemName: "book.open")
                                Text("Read Book")
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
        // Check if PDF file exists
        hasFile = FileStorage.bookFileExists(for: book.id)
        
        // Get file size
        if let size = FileStorage.bookFileSize(for: book.id) {
            fileSize = formatFileSize(size)
        } else {
            fileSize = ""
        }
        
        // Get page count from PDF
        if hasFile {
            loadPageCount()
        } else {
            pageCount = 0
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
            let pdfURL = try FileStorage.pdfURL(for: book.id)
            try PDFService.append(images: images, toPDFAt: pdfURL)
            
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
}
