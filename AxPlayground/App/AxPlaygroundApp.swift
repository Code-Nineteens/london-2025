//
//  AxPlaygroundApp.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import SwiftUI

@main
struct AxPlaygroundApp: App {
    
    @StateObject private var actionMonitor = UserActionMonitor.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        MenuBarExtra("AxPlayground", systemImage: "bolt.fill") {
            VStack(alignment: .leading, spacing: 12) {
                // Action Monitor toggle
                Button {
                    if actionMonitor.isMonitoring {
                        actionMonitor.stopMonitoring()
                    } else {
                        actionMonitor.startMonitoring { action in
                            let icon: String
                            switch action.actionType {
                            case .appLaunched: icon = "app.badge.fill"
                            case .appActivated: icon = "macwindow"
                            case .appQuit: icon = "xmark.app.fill"
                            case .buttonClicked: icon = "hand.tap.fill"
                            case .textEntered: icon = "keyboard.fill"
                            case .focusChanged: icon = "eye.fill"
                            case .menuSelected: icon = "list.bullet"
                            case .windowOpened: icon = "macwindow.badge.plus"
                            case .windowClosed: icon = "macwindow.badge.minus"
                            }
                            
                            NotificationManager.shared.show(
                                title: "\(action.actionType.rawValue) \(action.appName)",
                                message: action.details,
                                icon: icon
                            )
                            
                            // Log to file
                            let timestamp = ISO8601DateFormatter().string(from: Date())
                            let logLine = "[\(timestamp)] \(action.actionType.rawValue) [\(action.appName)] \(action.details)\n"
                            
                            if let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
                                let fileURL = desktopURL.appendingPathComponent("user_actions_log.txt")
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
                        }
                    }
                } label: {
                    Label(
                        actionMonitor.isMonitoring ? "Stop Action Log" : "Start Action Log",
                        systemImage: actionMonitor.isMonitoring ? "stop.circle.fill" : "play.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(actionMonitor.isMonitoring ? .red : .accentColor)
                
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
                .buttonStyle(.borderedProminent)
                
                Button {
                    MailHelper.openMailApp()
                } label: {
                    Label("Open Mail", systemImage: "envelope.fill")
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
