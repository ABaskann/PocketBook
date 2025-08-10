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

    var body: some View {
        NavigationStack {
            Form {
                Section("Book Info") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                }
                
                Section("Content") {
                    Button("Scan Document Pages") {
                        showingScanner = true
                    }
                    
                    if !scannedImages.isEmpty {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.green)
                            Text("\(scannedImages.count) pages scanned")
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Section("Cover") {
                    if let img = coverImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 180)
                            .cornerRadius(8)
                    }
                    
                    HStack {
                        Button("Select Cover Image") {
                            showingPicker = true
                        }
                        
                        if !scannedImages.isEmpty {
                            Button("Use First Page as Cover") {
                                coverImage = scannedImages.first
                            }
                        }
                    }
                }
                
                if isProcessing {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Processing and saving book...")
                        }
                    }
                }
            }
            .navigationTitle("Add Book")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || scannedImages.isEmpty || isProcessing)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
        
        // Auto-set title if empty
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            title = "Scanned Document \(Date().formatted(date: .numeric, time: .omitted))"
        }
        
        // Auto-set cover image if not already set
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
                // Create book
                let book = Book(
                    id: UUID(),
                    title: title.trimmingCharacters(in: .whitespaces),
                    author: author.isEmpty ? nil : author,
                    coverImageData: coverImage?.jpegData(compressionQuality: 0.8),
                )
                
                print("Created book: \(book.title) with ID: \(book.id)")
                
                // Create PDF from scanned images
                let pdfData = try await createPDFFromImages(scannedImages)
                print("Created PDF with \(pdfData.count) bytes")
                
                // Save PDF file
                let fileURL = try FileStorage.saveBookFile(bookId: book.id, data: pdfData)
                print("Saved PDF to: \(fileURL)")
                
                // Save to database on main thread
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
                    // You might want to show an alert here
                }
            }
        }
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
                    
                    // Calculate scaling to fit image in page
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

enum BookError: Error {
    case pdfCreationFailed
    case fileStorageError
}
