//
//  PDFService.swift
//  PocketBook
//
//  Created by Armağan Başkan on 10.08.2025.
//


import UIKit
import PDFKit

struct PDFService {
    // Create or append images to existing PDF at url
    static func append(images: [UIImage], toPDFAt url: URL) throws {
        var allImages = [UIImage]()

        // If existing PDF present, convert its pages to images and keep them
        if FileManager.default.fileExists(atPath: url.path), let pdfDoc = PDFDocument(url: url) {
            for i in 0..<pdfDoc.pageCount {
                if let page = pdfDoc.page(at: i) {
                    let thumb = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
                    allImages.append(thumb)
                }
            }
        }

        // append new scanned images
        allImages.append(contentsOf: images)

        // write new PDF
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { context in
            for img in allImages {
                context.beginPage()
                img.draw(in: pageRect)
            }
        }
    }
}