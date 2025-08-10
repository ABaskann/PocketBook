//
//  ReaderViewWrapper.swift
//  PocketBook
//
//  Created by Armağan Başkan on 10.08.2025.
//


// ReaderViewWrapper.swift
import SwiftUI
import PDFKit
import SwiftData

struct ReaderViewWrapper: UIViewRepresentable {
    @ObservedObject var book: Book
    @Environment(\.modelContext) private var modelContext

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .systemBackground

        if let doc = loadDocument() {
            pdfView.document = doc
            let last = Int(book.lastReadPage)
            if last < (doc.pageCount) {
                if let page = doc.page(at: last) {
                    pdfView.go(to: page)
                }
            }
        }
        NotificationCenter.default.addObserver(context.coordinator,
                                               selector: #selector(context.coordinator.pageChanged(_:)),
                                               name: .PDFViewPageChanged,
                                               object: nil)
        pdfView.delegate = context.coordinator
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(book: book, modelContext: modelContext)
    }

    func loadDocument() -> PDFDocument? {
        do {
            let url = try FileStorage.pdfURL(for: book.id)
            if FileManager.default.fileExists(atPath: url.path) {
                return PDFDocument(url: url)
            }
        } catch { return nil }
        return nil
    }

    class Coordinator: NSObject, PDFViewDelegate {
        var book: Book
        private var modelContext: ModelContext
        
        init(book: Book, modelContext: ModelContext) {
            self.book = book
            self.modelContext = modelContext
            super.init()
        }
        
        @objc func pageChanged(_ note: Notification) {
            guard let pdfView = note.object as? PDFView,
                  let current = pdfView.currentPage,
                  let index = pdfView.document?.index(for: current) else { return }
            
            Task { @MainActor in
                self.book.lastReadPage = index
                self.book.updatedAt = Date()
                
                do {
                    try self.modelContext.save()
                } catch {
                    print("Failed to save context: \(error)")
                }
            }
        }
    }
}
