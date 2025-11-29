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
                    // Extract visible text from ALL applications on screen
                    let visibleText = ScreenTextExtractor.shared.extractAllScreenText()
                    print("📝 Extracted text from screen:\n\(visibleText)")
                    
                    // Save to file on Desktop
                    let timestamp = ISO8601DateFormatter().string(from: Date())
                    let fileName = "screen_text_\(timestamp.replacingOccurrences(of: ":", with: "-")).txt"
                    let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                    let fileURL = desktopURL.appendingPathComponent(fileName)
                    
                    do {
                        try visibleText.write(to: fileURL, atomically: true, encoding: .utf8)
                        
                        // Open the file in TextEdit
                        NSWorkspace.shared.open(fileURL)
                        
                        NotificationManager.shared.show(
                            title: "Text Extracted",
                            message: "Saved to Desktop: \(fileName)",
                            icon: "doc.text.fill"
                        )
                    } catch {
                        NotificationManager.shared.show(
                            title: "Error",
                            message: "Failed to save: \(error.localizedDescription)",
                            icon: "exclamationmark.triangle.fill"
                        )
                    }
                } label: {
                    Label("Extract Screen Text", systemImage: "text.viewfinder")
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    NotificationManager.shared.show(
                        title: "Suggestion",
                        message: "You can use this app to test accessibility features.",
                        icon: "bolt.fill"
                    )
                } label: {
                    Label("Show suggestion", systemImage: "bell.fill")
                }
                .buttonStyle(.bordered)
                
                Divider()
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .menuBarExtraStyle(.window)
    }
}
