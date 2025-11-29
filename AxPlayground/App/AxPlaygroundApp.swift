//
//  AxPlaygroundApp.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import SwiftUI

@main
struct AxPlaygroundApp: App {
    
    @State private var items: [String] = [
        "Jakie zasady w cursor rules?",
        "Update intro and configuration for expo",
        "Dodanie opcji getLicense do DRM"
    ]
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        MenuBarExtra("AxPlayground", systemImage: "bolt.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NotificationManager.shared.show(
                        title: "Suggestion",
                        message: "You can use this app to test accessibility features.",
                        icon: "bolt.fill"
                    )
                } label: {
                    Label("Show suggestion", systemImage: "bell.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Zakończ", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .menuBarExtraStyle(.window)
    }
}
