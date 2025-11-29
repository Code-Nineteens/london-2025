//
//  AxPlaygroundApp.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import SwiftUI

@main
struct AxPlaygroundApp: App {
    
    @StateObject private var textMonitor = ScreenTextMonitor.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        MenuBarExtra("AxPlayground", systemImage: "bolt.fill") {
            VStack(alignment: .leading, spacing: 12) {
                // Monitor toggle
                Button {
                    if textMonitor.isMonitoring {
                        textMonitor.stopMonitoring()
                    } else {
                        textMonitor.startMonitoring { change in
                            // Show notification for each text change
                            let typeIcon: String
                            let typeText: String
                            
                            switch change.changeType {
                            case .added:
                                typeIcon = "plus.circle.fill"
                                typeText = "New text"
                            case .modified:
                                typeIcon = "pencil.circle.fill"
                                typeText = "Changed"
                            case .removed:
                                typeIcon = "minus.circle.fill"
                                typeText = "Removed"
                            }
                            
                            // Only show content for Added/Modified. For Removed, just show generic message to avoid confusion with old history.
                            let message: String
                            if change.changeType == .removed {
                                message = "Element disappeared"
                            } else {
                                message = String(change.newText.prefix(80))
                            }
                            
                            NotificationManager.shared.show(
                                title: "\(typeText) in \(change.appName)",
                                message: message,
                                icon: typeIcon
                            )
                            
                            // Log to file (keep full details for debugging)
                            let timestamp = ISO8601DateFormatter().string(from: Date())
                            let logLine = "[\(timestamp)] [\(change.appName)] \(typeText): \"\(change.newText)\" (Old: \"\(change.oldText ?? "")\")\n"
                            
                            if let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
                                let fileURL = desktopURL.appendingPathComponent("ax_changes_log.txt")
                                if !FileManager.default.fileExists(atPath: fileURL.path) {
                                    try? "".write(to: fileURL, atomically: true, encoding: .utf8)
                                }
                                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                                    fileHandle.seekToEndOfFile()
                                    if let data = logLine.data(using: .utf8) {
                                        fileHandle.write(data)
                                    }
                                    try? fileHandle.close()
                                }
                            }
                            
                            print("📝 [\(change.appName)] \(typeText): \(change.newText)")
                        }
                    }
                } label: {
                    Label(
                        textMonitor.isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                        systemImage: textMonitor.isMonitoring ? "stop.circle.fill" : "play.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(textMonitor.isMonitoring ? .red : .accentColor)
                
                // Extract once
                Button {
                    let visibleText = ScreenTextExtractor.shared.extractAllScreenText()
                    print("📝 Extracted text from screen:\n\(visibleText)")
                    
                    let timestamp = ISO8601DateFormatter().string(from: Date())
                    let fileName = "screen_text_\(timestamp.replacingOccurrences(of: ":", with: "-")).txt"
                    let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
                    let fileURL = desktopURL.appendingPathComponent(fileName)
                    
                    do {
                        try visibleText.write(to: fileURL, atomically: true, encoding: .utf8)
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
