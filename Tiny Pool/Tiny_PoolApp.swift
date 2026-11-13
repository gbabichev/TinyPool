//
//  Tiny_PoolApp.swift
//  Tiny Pool
//
//  Created by George Babichev on 11/13/26.
//

import SwiftUI

@main
struct Tiny_PoolApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 640)
        #endif
    }
}
