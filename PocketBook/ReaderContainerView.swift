//
//  ReaderContainerView.swift
//  PocketBook
//
//  Created by Armağan Başkan on 10.08.2025.
//


// ReaderContainerView.swift
import SwiftUI
import SwiftData

struct ReaderContainerView: View {
    @ObservedObject var book: Book
    var body: some View {
        ReaderViewWrapper(book: book)
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}