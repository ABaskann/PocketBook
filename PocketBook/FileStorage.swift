//
//  FileStorage.swift
//  PocketBook
//
//  Created by Armağan Başkan on 10.08.2025.
//

import Foundation

enum FileStorage {
    static let booksDirectoryName = "Books"

    static func booksDirectory() throws -> URL {
        let fm = FileManager.default
        let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let booksDir = docs.appendingPathComponent(booksDirectoryName, isDirectory: true)
        if !fm.fileExists(atPath: booksDir.path) {
            try fm.createDirectory(at: booksDir, withIntermediateDirectories: true)
        }
        return booksDir
    }

    static func bookDirectory(for bookID: UUID) throws -> URL {
        let booksDir = try booksDirectory()
        let bookDir = booksDir.appendingPathComponent(bookID.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: bookDir.path) {
            try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        }
        return bookDir
    }

    static func pdfURL(for bookID: UUID) throws -> URL {
        let bookDir = try bookDirectory(for: bookID)
        return bookDir.appendingPathComponent("book.pdf")
    }
    
    // New method to save book file data
    static func saveBookFile(bookId: UUID, data: Data) throws -> URL {
        let pdfURL = try pdfURL(for: bookId)
        try data.write(to: pdfURL)
        print("Saved \(data.count) bytes to \(pdfURL)")
        return pdfURL
    }
    
    // Helper method to check if a book file exists
    static func bookFileExists(for bookID: UUID) -> Bool {
        do {
            let pdfURL = try pdfURL(for: bookID)
            return FileManager.default.fileExists(atPath: pdfURL.path)
        } catch {
            return false
        }
    }
    
    // Helper method to get file size
    static func bookFileSize(for bookID: UUID) -> Int64? {
        do {
            let pdfURL = try pdfURL(for: bookID)
            let attributes = try FileManager.default.attributesOfItem(atPath: pdfURL.path)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
    
    // Method to delete a book's files
    static func deleteBookFiles(for bookID: UUID) throws {
        let bookDir = try bookDirectory(for: bookID)
        try FileManager.default.removeItem(at: bookDir)
    }
}
