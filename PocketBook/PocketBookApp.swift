//
//  PocketBookApp.swift
//  PocketBook
//
//  Created by Armağan Başkan on 10.08.2025.
//

import SwiftUI

@main
struct PocketBookApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
                           .modelContainer(for: [Book.self])
        }
    }
}
