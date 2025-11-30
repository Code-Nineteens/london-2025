//
//  ScreenActivityLogger.swift
//  AxPlayground
//
//  Created on 29/11/2025.
//

import Cocoa
import ApplicationServices
import Combine

/// Logs all screen text changes and user actions to a file every 1.5 seconds
@MainActor
final class ScreenActivityLogger: ObservableObject {
    
    static let shared = ScreenActivityLogger()
    
    @Published var isLogging = false
    @Published var logFilePath: String?
    
    private var timer: Timer?
    private var previousScreenText: String = ""
    private var fileHandle: FileHandle?
    private var logFileURL: URL?
    private let textExtractor = ScreenTextExtractor.shared
    
    // Tracking dla stabilnych tekstów
    private var stableTexts: Set<String> = []  // Teksty które są już uznane za "stare"
    private var candidateTexts: Set<String> = []  // Teksty widziane raz, czekają na potwierdzenie
    private var textHistory: [String: [String]] = [:]  // Historia wartości dla każdego tekstu (wykrywanie auto-zmian)
    
    // JSON batching dla lepszej wydajności
    private var jsonBuffer: [[String: Any]] = []
    private let maxBufferSize = 10  // Zapisuj co 10 eventów
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start logging screen text changes and user actions
    func startLogging() {
        stopLogging()
        
        setupLogFile()
        isLogging = true
        
        // Take initial snapshot
        previousScreenText = textExtractor.extractAllScreenText()
        // Inicjalizuj stable texts z pierwszym snapshotem
        let initialLines = previousScreenText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 10 }
        stableTexts = Set(initialLines)
        candidateTexts.removeAll()
        
        // Nie logujemy system messages - tylko faktyczne eventy
        
        // Start periodic extraction every 1.5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndLogChanges()
            }
        }
        
        print("📝 Screen activity logging started")
        print("📁 Log file: \(logFileURL?.path ?? "unknown")")
    }
    
    /// Stop logging
    func stopLogging() {
        timer?.invalidate()
        timer = nil
        
        // Flush remaining buffer before closing
        flushJSONBuffer()
        
        closeLogFile()
        isLogging = false
        previousScreenText = ""
        stableTexts.removeAll()
        candidateTexts.removeAll()
        textHistory.removeAll()
        
        print("⏹️ Screen activity logging stopped")
    }
    
    /// Log a user action (called from UserActionMonitor)
    func logUserAction(_ action: UserActionMonitor.UserAction) {
        guard isLogging else { return }
        
        let jsonObject: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: action.timestamp),
            "type": "action",
            "action_name": action.rawNotification ?? "Unknown",
            "app": action.appName,
            "details": action.details
        ]
        
        addToBuffer(jsonObject)
    }
    
    // MARK: - Private Methods
    
    private func setupLogFile() {
        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            print("❌ Could not find desktop directory")
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        let filename = "screen_activity_log_\(dateString).jsonl"  // JSON Lines format
        
        logFileURL = desktopURL.appendingPathComponent(filename)
        logFilePath = logFileURL?.path
        
        // Create file if it doesn't exist
        if let url = logFileURL {
            // JSON Lines format - każda linia to osobny JSON object
            let header = ""  // Brak headera w JSONL
            try? header.write(to: url, atomically: true, encoding: .utf8)
            
            // Open file handle for appending
            fileHandle = try? FileHandle(forWritingTo: url)
            fileHandle?.seekToEndOfFile()
        }
    }
    
    private func closeLogFile() {
        try? fileHandle?.close()
        fileHandle = nil
    }
    
    private func checkAndLogChanges() {
        let currentText = textExtractor.extractAllScreenText()
        
        // Quick check - if text hasn't changed at all, skip everything
        guard currentText != previousScreenText else { return }
        
        // Konwertuj na set linii z filtrowaniem w jednym przejściu
        let currentLines = currentText.components(separatedBy: .newlines)
            .lazy  // Lazy evaluation
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 10 }
        let currentSet = Set(currentLines)
        
        // Early exit if no meaningful content
        guard !currentSet.isEmpty else {
            previousScreenText = currentText
            return
        }
        
        // 1. Znajdź teksty które pojawiły się pierwszy raz (nie były ani stable ani candidate)
        let firstTimeSeen = currentSet.subtracting(stableTexts).subtracting(candidateTexts)
        
        // 2. Znajdź teksty które pojawiły się drugi raz (były candidate, są teraz w current)
        let confirmedNew = candidateTexts.intersection(currentSet)
        
        // 3. Zapisz confirmed new jako naprawdę nowe
        if !confirmedNew.isEmpty {
            logNewTexts(Array(confirmedNew))
            // Przenieś confirmed do stable
            stableTexts.formUnion(confirmedNew)
        }
        
        // 4. Zaktualizuj candidates - teksty widziane pierwszy raz stają się kandydatami
        candidateTexts = firstTimeSeen
        
        // 5. Usuń z stable teksty które zniknęły całkowicie (co 5 cyklów, nie za każdym razem)
        if stableTexts.count > 1000 {  // Tylko gdy jest dużo
            stableTexts = stableTexts.intersection(currentSet.union(candidateTexts))
        }
        
        previousScreenText = currentText
    }
    
    private func logNewTexts(_ texts: [String]) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        
        var logged = 0
        for text in texts {
            guard logged < 10 else { break }  // Max 10 na raz
            
            if isMeaningfulText(text) && !isSelfChangingText(text) {
                let jsonObject: [String: Any] = [
                    "timestamp": timestamp,
                    "type": "text_added",
                    "text": text,
                    "app": app,
                    "length": text.count
                ]
                
                addToBuffer(jsonObject)
                
                // Pokazuj w overlay
                TextChangesOverlayController.shared.addChange(text: text, type: .added)
                logged += 1
            }
        }
    }
    
    
    /// Sprawdza czy tekst jest znaczący (nie tylko cyfry, symbole, itp.)
    private func isMeaningfulText(_ text: String) -> Bool {
        // Musi zawierać przynajmniej jedną literę
        let hasLetters = text.contains(where: { $0.isLetter })
        
        // Nie powinien składać się tylko z cyfr i symboli
        let alphanumericCount = text.filter { $0.isLetter || $0.isNumber }.count
        let meaningfulRatio = Double(alphanumericCount) / Double(text.count)
        
        return hasLetters && meaningfulRatio > 0.3
    }
    
    /// Wykrywa teksty które się same zmieniają (zegary, liczniki, losowe ID)
    private func isSelfChangingText(_ text: String) -> Bool {
        // Wzorce auto-zmieniających się tekstów
        
        // 1. Tylko cyfry i separatory (np. "12:34:56", "100%", "1,234")
        let digitAndSeparatorPattern = "^[0-9:,.%\\s-]+$"
        if text.range(of: digitAndSeparatorPattern, options: .regularExpression) != nil {
            return true
        }
        
        // 2. Wzorce czasu (HH:MM, HH:MM:SS)
        let timePattern = "^\\d{1,2}:\\d{2}(:\\d{2})?(\\s*(AM|PM|am|pm))?$"
        if text.range(of: timePattern, options: .regularExpression) != nil {
            return true
        }
        
        // 3. Procentowe (85%, 100%)
        if text.hasSuffix("%") && text.dropLast().allSatisfy({ $0.isNumber || $0.isWhitespace }) {
            return true
        }
        
        // 4. UUID/Hash patterns (losowe ciągi)
        let hexPattern = "^[0-9a-fA-F-]{8,}$"
        if text.range(of: hexPattern, options: .regularExpression) != nil {
            return true
        }
        
        // 5. Loading indicators ("...", "Loading...", itp.)
        if text.contains("...") || text.lowercased().contains("loading") || text.lowercased().contains("spinner") {
            return true
        }
        
        // 6. Sprawdzanie historii - jeśli ten sam base text ma różne wartości
        let baseText = extractBasePattern(text)
        if var history = textHistory[baseText] {
            history.append(text)
            if history.count > 3 {
                history = Array(history.suffix(3))  // Zachowaj ostatnie 3
            }
            textHistory[baseText] = history
            
            // Jeśli ostatnie 3 wartości to różne liczby -> auto-zmieniający się
            let uniqueValues = Set(history)
            if uniqueValues.count == history.count && history.count >= 3 {
                return true
            }
        } else {
            textHistory[baseText] = [text]
        }
        
        return false
    }
    
    /// Wyciąga bazowy pattern z tekstu (np. "Battery: 85%" -> "Battery: X%")
    private func extractBasePattern(_ text: String) -> String {
        var pattern = text
        // Zamień liczby na X
        pattern = pattern.replacingOccurrences(of: "\\d+", with: "X", options: .regularExpression)
        return pattern
    }
    
    /// Dodaje JSON do bufora (batch writing)
    private func addToBuffer(_ object: [String: Any]) {
        jsonBuffer.append(object)
        
        if jsonBuffer.count >= maxBufferSize {
            flushJSONBuffer()
        }
    }
    
    /// Zapisuje wszystkie buffered JSON objects do pliku
    private func flushJSONBuffer() {
        guard !jsonBuffer.isEmpty else { return }
        
        var allLines = ""
        for object in jsonBuffer {
            if let jsonData = try? JSONSerialization.data(withJSONObject: object, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                allLines += jsonString + "\n"
            }
        }
        
        if let data = allLines.data(using: .utf8) {
            fileHandle?.write(data)
        }
        
        jsonBuffer.removeAll(keepingCapacity: true)
    }
    
}
