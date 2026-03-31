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
                .frame(
                    minWidth: 820, idealWidth: 1200,
                    minHeight: 600, idealHeight: 900
                )
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 900)
        #endif
    }
}
