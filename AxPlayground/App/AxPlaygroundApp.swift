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
            MenuBarView(items: items)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            itemsSection
            newItemButton
            Divider()
                .padding(.vertical, 6)
            actionButtons
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 280)
    }
    
    // MARK: - Sections
    
    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SzpontOS")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            
            ForEach(items, id: \.self) { item in
                MenuItemButton(title: item) {
                    print("Selected: \(item)")
                }
            }
        }
        .padding(.bottom, 4)
    }
    
    private var newItemButton: some View {
        MenuItemButton(title: "blabla", fontWeight: .medium) {
            print("blabla")
        }
    }
    
    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuItemButton(title: "Open spontOS") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            
            MenuItemButton(title: "Settings") {
                print("Settings")
            }
            
            MenuItemButton(title: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - Menu Item Button

struct MenuItemButton: View {
    
    let title: String
    var fontWeight: Font.Weight = .regular
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .fontWeight(fontWeight)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
