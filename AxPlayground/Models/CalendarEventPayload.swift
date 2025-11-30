//
//  CalendarEventPayload.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation

/// Structured output for calendar event composition
struct CalendarEventPayload: Sendable {
    /// Whether a calendar event should be created
    let shouldCreateEvent: Bool

    /// Short one-line description of inferred task
    let inferredTask: String

    /// Confidence score 0.0-1.0
    let confidence: Double

    /// List of context sources used (if any)
    let valueAddedContextUsed: [String]

    /// Event title
    let eventTitle: String

    /// Event start date/time (ISO 8601 format from LLM)
    let startTime: String

    /// Event end date/time (ISO 8601 format from LLM)
    let endTime: String

    /// Event location (optional)
    let location: String?

    /// Event notes/description
    let notes: String?

    /// Attendee email to invite (person who sent the notification)
    let attendeeEmail: String?

    /// Attendee name
    let attendeeName: String?

    /// Missing info if cannot create (e.g., "need event time")
    let missingInfo: String?

    /// Timestamp when generated
    let timestamp: Date

    // MARK: - Coding Keys for JSON parsing

    enum CodingKeys: String, CodingKey {
        case shouldCreateEvent = "should_create_event"
        case inferredTask = "inferred_task"
        case confidence
        case valueAddedContextUsed = "value_added_context_used"
        case eventTitle = "event_title"
        case startTime = "start_time"
        case endTime = "end_time"
        case location
        case notes
        case attendeeEmail = "attendee_email"
        case attendeeName = "attendee_name"
        case missingInfo = "missing_info"
    }

    /// Check if event is actionable
    var isActionable: Bool {
        shouldCreateEvent && confidence >= 0.7 && !eventTitle.isEmpty && !startTime.isEmpty
    }

    /// Human-readable reason why event cannot be created
    var whyNotCreatable: String? {
        guard !shouldCreateEvent else { return nil }
        return missingInfo ?? "Not enough information to create calendar event"
    }

    /// Parse start time string to Date
    var startDate: Date? {
        parseDateTime(startTime)
    }

    /// Parse end time string to Date
    var endDate: Date? {
        parseDateTime(endTime)
    }

    private func parseDateTime(_ string: String) -> Date? {
        let formatters: [Any] = [
            ISO8601DateFormatter(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm"
                return f
            }()
        ]

        for formatter in formatters {
            if let f = formatter as? ISO8601DateFormatter {
                if let date = f.date(from: string) {
                    return date
                }
            } else if let f = formatter as? DateFormatter {
                if let date = f.date(from: string) {
                    return date
                }
            }
        }
        return nil
    }

    /// Empty/nil payload for when no event should be created
    static var empty: CalendarEventPayload {
        CalendarEventPayload(
            shouldCreateEvent: false,
            inferredTask: "",
            confidence: 0.0,
            valueAddedContextUsed: [],
            eventTitle: "",
            startTime: "",
            endTime: "",
            location: nil,
            notes: nil,
            attendeeEmail: nil,
            attendeeName: nil,
            missingInfo: nil,
            timestamp: Date()
        )
    }
}

// MARK: - Custom Decodable (timestamp not from JSON)

extension CalendarEventPayload: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        shouldCreateEvent = try container.decode(Bool.self, forKey: .shouldCreateEvent)
        inferredTask = try container.decodeIfPresent(String.self, forKey: .inferredTask) ?? ""
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.0
        valueAddedContextUsed = try container.decodeIfPresent([String].self, forKey: .valueAddedContextUsed) ?? []
        eventTitle = try container.decodeIfPresent(String.self, forKey: .eventTitle) ?? ""
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime) ?? ""
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime) ?? ""
        location = try container.decodeIfPresent(String.self, forKey: .location)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        attendeeEmail = try container.decodeIfPresent(String.self, forKey: .attendeeEmail)
        attendeeName = try container.decodeIfPresent(String.self, forKey: .attendeeName)
        missingInfo = try container.decodeIfPresent(String.self, forKey: .missingInfo)

        // Timestamp is always set to now (not from JSON)
        timestamp = Date()
    }
}
