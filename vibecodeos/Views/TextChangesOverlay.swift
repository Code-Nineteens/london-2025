//
//  TextChangesOverlay.swift
//  AxPlayground
//
//  Created on 29/11/2025.
//

import SwiftUI
import Combine

/// Kontroler zarządzający floating overlay, które pokazuje na żywo wykrywane zmiany tekstu na ekranie
/// Wyświetla zielone (dodane) i czerwone (usunięte) teksty w czasie rzeczywistym
class TextChangesOverlayController: ObservableObject {
    static let shared = TextChangesOverlayController()
    
    /// Lista ostatnich wykrytych zmian (max 30)
    @Published var recentChanges: [DetectedChange] = []
    
    /// Czy overlay jest aktualnie widoczne
    @Published var isVisible = false
    
    /// Referencja do floating window
    private var window: NSWindow?
    
    /// Pojedyncza wykryta zmiana tekstu na ekranie
    struct DetectedChange: Identifiable {
        let id = UUID()
        /// Kiedy zmiana została wykryta
        let timestamp: Date
        /// Treść tekstu, który się zmienił
        let text: String
        /// Typ zmiany (dodany lub usunięty)
        let changeType: ChangeType
        
        enum ChangeType {
            case added      // Nowy tekst pojawił się na ekranie
            case removed    // Tekst zniknął z ekranu
        }
        
        /// Kolor dla typu zmiany (zielony dla dodanych, czerwony dla usuniętych)
        var color: Color {
            switch changeType {
            case .added: return .green
            case .removed: return .red
            }
        }
        
        /// Ikona SF Symbol dla typu zmiany
        var icon: String {
            switch changeType {
            case .added: return "plus.circle.fill"
            case .removed: return "minus.circle.fill"
            }
        }
    }
    
    private init() {}
    
    /// Pokazuje overlay na ekranie
    func show() {
        if window == nil {
            createWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        isVisible = true
    }
    
    /// Ukrywa overlay
    func hide() {
        window?.orderOut(nil)
        isVisible = false
    }
    
    /// Przełącza widoczność overlay (toggle)
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    /// Dodaje nową zmianę do listy (wywołane przez ScreenActivityLogger)
    /// - Parameters:
    ///   - text: Treść wykrytego tekstu
    ///   - type: Typ zmiany (added/removed)
    func addChange(text: String, type: DetectedChange.ChangeType) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Deduplikacja - nie dodawaj jeśli ten sam tekst był już niedawno (w ostatnich 5 sekundach)
            let now = Date()
            let recentDuplicate = self.recentChanges.first(where: { change in
                change.text == text && 
                change.changeType == type &&
                now.timeIntervalSince(change.timestamp) < 5.0
            })
            
            if recentDuplicate != nil {
                return // Pomijamy duplikaty
            }
            
            let change = DetectedChange(timestamp: Date(), text: text, changeType: type)
            
            // Dodaj na początek listy (najnowsze na górze)
            self.recentChanges.insert(change, at: 0)
            // Zachowaj tylko 30 ostatnich zmian
            if self.recentChanges.count > 30 {
                self.recentChanges = Array(self.recentChanges.prefix(30))
            }
        }
    }
    
    /// Czyści całą listę zmian
    func clear() {
        recentChanges.removeAll()
    }
    
    /// Tworzy i konfiguruje floating window overlay
    private func createWindow() {
        let contentView = TextChangesOverlayView(controller: self)
        
        // Stwórz semi-transparent floating window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Live Text Changes"
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        window.level = .floating  // Zawsze na wierzchu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: contentView)
        window.isMovableByWindowBackground = true  // Można przesuwać
        
        // Umieść w prawym górnym rogu ekranu
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.maxX - windowFrame.width - 20
            let y = screenFrame.maxY - windowFrame.height - 20
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        self.window = window
    }
}

/// Główny widok overlay pokazujący listę zmian tekstu
struct TextChangesOverlayView: View {
    @ObservedObject var controller: TextChangesOverlayController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "text.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(.white)
                
                Text("Live Text Changes")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Button(action: { controller.clear() }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Clear all")
            }
            .padding()
            .background(Color.white.opacity(0.1))
            
            Divider()
            
            // Changes list
            if controller.recentChanges.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.3))
                    
                    Text("Waiting for text changes...")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(controller.recentChanges) { change in
                            ChangeRow(change: change)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 300, minHeight: 400)
    }
}

/// Pojedynczy wiersz pokazujący jedną zmianę tekstu
struct ChangeRow: View {
    let change: TextChangesOverlayController.DetectedChange
    
    /// Formatuje czas jako "just now", "5s ago", "2m ago" itp.
    private var timeAgo: String {
        let interval = Date().timeIntervalSince(change.timestamp)
        if interval < 1 {
            return "just now"
        } else if interval < 60 {
            return "\(Int(interval))s ago"
        } else {
            return "\(Int(interval / 60))m ago"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: change.icon)
                .font(.body)
                .foregroundStyle(change.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(change.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(timeAgo)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(change.color.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(change.color.opacity(0.3), lineWidth: 1)
        )
    }
}
