//
//  LibraryView.swift
//  PocketBook
//
//  Created by Armağan Başkan on 10.08.2025.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Query(sort: \Book.createdAt, order: .reverse) var books: [Book]
    @Environment(\.modelContext) private var modelContext

    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(books, id: \.id) { book in
                    NavigationLink {
                        BookDetailView(book: book)
                    } label: {
                        HStack(spacing: 12) {
                            if let data = book.coverImageData, let ui = UIImage(data: data) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 70)
                                    .clipped()
                                    .cornerRadius(6)
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 50, height: 70)
                                    .cornerRadius(6)
                                    .overlay(Text("No cover").font(.caption))
                            }
                            VStack(alignment: .leading) {
                                Text(book.title).font(.headline)
                                if let author = book.author { Text(author).font(.subheadline).foregroundColor(.secondary) }
                                Text("Pages: —").font(.caption).foregroundColor(.secondary) // page count can be read from PDF
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("My Library")
            .toolbar {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showingAdd) {
                AddBookView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            let book = books[idx]
            modelContext.delete(book)
            // delete files
            try? FileManager.default.removeItem(at: try FileStorage.bookDirectory(for: book.id))
        }
        try? modelContext.save()
    }
}
