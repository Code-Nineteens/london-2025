//
//  ScreenOCRService.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation
import Vision
import AppKit
import Combine
import CoreGraphics

/// Service for extracting text from screen using OCR (Vision framework)
@MainActor
final class ScreenOCRService: ObservableObject {
    
    static let shared = ScreenOCRService()
    
    @Published var isProcessing = false
    @Published var lastExtractedTexts: [ExtractedText] = []
    @Published var lastError: String?
    
    /// Recognized text with position
    struct ExtractedText: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let boundingBox: CGRect
        let confidence: Float
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(text)
        }
        
        static func == (lhs: ExtractedText, rhs: ExtractedText) -> Bool {
            lhs.text == rhs.text
        }
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Capture and OCR the active window
    func captureAndOCR() async -> [ExtractedText] {
        guard !isProcessing else { 
            print("🔍 OCR: Already processing, skipping")
            return [] 
        }
        isProcessing = true
        defer { isProcessing = false }
        
        print("🔍 OCR: Starting capture...")
        
        do {
            // Capture active window screenshot
            guard let image = await captureActiveWindow() else {
                print("🔍 OCR: ❌ Failed to capture window - check Screen Recording permission!")
                return []
            }
            
            print("🔍 OCR: ✅ Captured image \(image.width)x\(image.height)")
            
            // Perform OCR
            let texts = try await performOCR(on: image)
            lastExtractedTexts = texts
            
            print("🔍 OCR: ✅ Found \(texts.count) text regions")
            if !texts.isEmpty {
                // Show more samples to debug what's being captured
                print("🔍 OCR: === ALL TEXTS ===")
                for (i, t) in texts.prefix(15).enumerated() {
                    print("🔍 OCR [\(i)]: \(t.text.prefix(80))")
                }
                print("🔍 OCR: === END ===")
            }
            return texts
            
        } catch {
            lastError = error.localizedDescription
            print("🔍 OCR: ❌ Error: \(error)")
            return []
        }
    }
    
    /// Get only text strings (without positions)
    func captureAndGetTexts() async -> Set<String> {
        let extracted = await captureAndOCR()
        return Set(extracted.map(\.text))
    }
    
    // MARK: - Screen Capture
    
    private func captureActiveWindow() async -> CGImage? {
        // Always capture main display - window capture is unreliable
        return captureMainDisplay()
    }
    
    /// Capture main display using screencapture
    private func captureMainDisplay() -> CGImage? {
        // Save to Desktop for debugging
        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("ocr_debug.png")
        
        // -x = no sound
        let arguments = ["-x", desktopURL.path]
        
        print("🔍 screencapture: saving to \(desktopURL.path)")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                print("🔍 screencapture: ❌ exit code \(process.terminationStatus)")
                return nil
            }
            
            guard FileManager.default.fileExists(atPath: desktopURL.path) else {
                print("🔍 screencapture: ❌ file not created")
                return nil
            }
            
            guard let image = NSImage(contentsOf: desktopURL),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                print("🔍 screencapture: ❌ failed to load image")
                return nil
            }
            
            print("🔍 screencapture: ✅ \(cgImage.width)x\(cgImage.height) - saved to Desktop/ocr_debug.png")
            
            return cgImage
        } catch {
            print("🔍 screencapture: ❌ error: \(error)")
            return nil
        }
    }
    
    // MARK: - OCR Processing
    
    private func performOCR(on image: CGImage) async throws -> [ExtractedText] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("🔍 OCR request error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    print("🔍 OCR: no observations")
                    continuation.resume(returning: [])
                    return
                }
                
                print("🔍 OCR: raw observations count: \(observations.count)")
                
                var results: [ExtractedText] = []
                
                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else { continue }
                    
                    let text = topCandidate.string
                    let confidence = topCandidate.confidence
                    
                    // Lower threshold - accept more text
                    guard confidence > 0.3, text.count > 1 else { continue }
                    
                    // Convert normalized coordinates to pixels
                    let boundingBox = observation.boundingBox
                    let rect = CGRect(
                        x: boundingBox.origin.x * CGFloat(image.width),
                        y: (1 - boundingBox.origin.y - boundingBox.height) * CGFloat(image.height),
                        width: boundingBox.width * CGFloat(image.width),
                        height: boundingBox.height * CGFloat(image.height)
                    )
                    
                    results.append(ExtractedText(
                        text: text,
                        boundingBox: rect,
                        confidence: confidence
                    ))
                }
                
                continuation.resume(returning: results)
            }
            
            // Try FAST mode - sometimes more reliable
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false  // Disable - might cause issues
            request.recognitionLanguages = ["en-US", "pl-PL"]  // English first
            
            // Set minimum text height (fraction of image height)
            request.minimumTextHeight = 0.01  // Very small - catch all text
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("🔍 OCR handler error: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
}
