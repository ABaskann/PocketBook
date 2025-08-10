//
//  Book.swift
//  PocketBook
//
//  Created by Armağan Başkan on 10.08.2025.
//


import Foundation
import SwiftData

@Model
final class Book:ObservableObject {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String?
    var coverImageData: Data?
    var createdAt: Date
    var updatedAt: Date
    var lastReadPage: Int

    init(id: UUID = UUID(), title: String, author: String? = nil, coverImageData: Data? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImageData = coverImageData
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastReadPage = 0
    }
}
