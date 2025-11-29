//
//  AxPlaygroundApp.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import SwiftUI

@main
struct AxPlaygroundApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        MenuBarExtra("AxPlayground", systemImage: "bolt.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("AxPlayground")
                    .font(.headline)

                Button("Pokaż okno") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }

                Button("Zakończ") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(16)
            .frame(width: 260)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
        .menuBarExtraStyle(.window)
    }
}
