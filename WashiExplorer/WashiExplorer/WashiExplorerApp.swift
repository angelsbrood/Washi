//
//  WashiExplorerApp.swift
//  WashiExplorer
//
//  Created by Nelly Moon on 3/29/26.
//

import SwiftUI

@main
struct WashiExplorerApp: App {
    var body: some Scene {
        WindowGroup("Washi Explorer") {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 820, minHeight: 600)
                #endif
        }
    }
}
