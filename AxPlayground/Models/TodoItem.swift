//
//  TodoItem.swift
//  AxPlayground
//
//  Created by Kamil Moskała on 29/11/2025.
//

import SwiftUI

// MARK: - Task Status

enum TaskStatus: String, CaseIterable {
    case idle
    case inProgress
    case completed

    var color: Color {
        switch self {
        case .idle:
            return .gray
        case .inProgress:
            return .yellow
        case .completed:
            return .green
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            return "circle"
        case .inProgress:
            return "circle.dotted"
        case .completed:
            return "checkmark.circle.fill"
        }
    }
}

// MARK: - Todo Item

struct TodoItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var status: TaskStatus

    init(id: UUID = UUID(), title: String, status: TaskStatus = .idle) {
        self.id = id
        self.title = title
        self.status = status
    }
}
