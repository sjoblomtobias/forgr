//
//  forgrApp.swift
//  forgr
//
//  Created by Tobias Sjöblom on 2026-09-08.
//

import SwiftUI

@main
struct forgrApp: App {
    @State private var appID = UUID()

    var body: some Scene {
        WindowGroup {
            SplashGateView(onRestart: { appID = UUID() })
                .id(appID)
        }
    }
}
