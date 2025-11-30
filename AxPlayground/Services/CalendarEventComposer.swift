//
//  CalendarEventComposer.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Foundation
import Combine

/// Composes calendar events based on detected intent and relevant context
@MainActor
final class CalendarEventComposer: ObservableObject {

    static let shared = CalendarEventComposer()

    // MARK: - Dependencies

    private let llmClient = AnthropicClient.shared
    private let contextRetriever = ContextRetriever.shared
    private let userProfileManager = UserProfileManager.shared

    // MARK: - State

    @Published var lastEvent: CalendarEventPayload?
    @Published var isComposing = false

    private init() {}

    // MARK: - Public API

    /// Main entry point: compose calendar event from detected intent
    func composeCalendarEvent(
        intent: String,
        recentEvents: [AXEvent],
        systemState: SystemState
    ) async -> CalendarEventPayload? {
        isComposing = true
        defer { isComposing = false }

        print("")
        print("📅═══════════════════════════════════════════════════")
        print("📅 CALENDAR EVENT COMPOSER STARTED")
        print("📅 Intent: \(intent)")
        print("📅═══════════════════════════════════════════════════")

        // 1. Retrieve relevant context from ContextStore
        let contextChunks = await contextRetriever.retrieve(intent: intent)
        let contextString = contextRetriever.buildContextString(chunks: contextChunks)
        print("📅 Retrieved \(contextChunks.count) context chunks")

        // 2. Build LLM prompt with context
        let prompt = buildCalendarPrompt(
            intent: intent,
            contextString: contextString,
            systemState: systemState
        )

        // Log full prompt for debugging
        print("")
        print("📅 ═══════════════════════════════════════════════════")
        print("📅 SENDING TO AI MODEL - FULL REQUEST")
        print("📅 ═══════════════════════════════════════════════════")
        print("📅 USER MESSAGE:")
        print("📅 ───────────────────────────────────────────────────")
        print(prompt)
        print("📅 ───────────────────────────────────────────────────")

        // 3. Call LLM for calendar event composition
        guard let event = await composeWithLLM(prompt: prompt) else {
            print("📅 ❌ LLM composition failed")
            return nil
        }

        print("📅 ✅ Calendar event composed!")
        print("📅 Title: \(event.eventTitle)")
        print("📅 Start: \(event.startTime)")
        print("📅 End: \(event.endTime)")
        print("📅 Attendee: \(event.attendeeEmail ?? "none")")
        print("📅═══════════════════════════════════════════════════")

        lastEvent = event
        return event
    }

    /// Quick check if text indicates calendar/meeting intent
    func detectsCalendarIntent(in text: String) -> Bool {
        let calendarKeywords = [
            // English
            "schedule", "meeting", "calendar", "event", "appointment",
            "let's meet", "catch up", "sync up", "call", "chat today",
            "meet today", "meet tomorrow", "coffee", "lunch",
            // Polish
            "spotkanie", "kalendarz", "umówmy się", "pogadajmy",
            "zadzwoń", "spotkajmy się"
        ]

        let textLower = text.lowercased()
        return calendarKeywords.contains { textLower.contains($0) }
    }

    // MARK: - LLM Prompt Building

    private func buildCalendarPrompt(
        intent: String,
        contextString: String,
        systemState: SystemState
    ) -> String {
        let userProfile = userProfileManager.profile
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        let currentTimeISO = dateFormatter.string(from: now)

        let readableDateFormatter = DateFormatter()
        readableDateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        let currentTimeReadable = readableDateFormatter.string(from: now)

        return """
        TASK: Create a calendar event based on the user's intent and context.
        use precise title when creating the events. use this format `Meeting with X.`

        USER INTENT: "\(intent)"

        CURRENT TIME: \(currentTimeISO)
        CURRENT TIME (readable): \(currentTimeReadable)

        USER: \(userProfile.name)

        CURRENT APP: \(systemState.activeApp)

        \(contextString)

        ⚠️ CONTEXT PRIORITY (MOST IMPORTANT):
        1. [Notification] = TOP PRIORITY - These contain the meeting request details!
        2. [Ocr] = Second priority - Current screen content
        3. Other context = Lower priority

        CONTEXT USAGE:
        - NOTIFICATIONS ARE THE PRIMARY SOURCE for meeting/event details!
        - Extract WHO sent the notification - they should be invited as attendee
        - Extract WHEN the meeting should happen from the notification content
        - If notification says "today" or "chat today" - schedule for today
        - If notification says "tomorrow" - schedule for tomorrow
        - Default meeting duration: 30 minutes for quick chats, 1 hour for meetings

        TIME INTERPRETATION:
        - "today" = use today's date, default to next available hour (round up)
        - "tomorrow" = use tomorrow's date
        - "morning" = 9:00 AM
        - "afternoon" = 2:00 PM
        - "evening" = 6:00 PM
        - "coffee" = 30 min meeting
        - "chat" or "quick call" = 30 min meeting
        - "meeting" = 1 hour meeting

        RULES:
        1. ALWAYS set should_create_event=true if there's any meeting/calendar intent
        2. Extract attendee info from [Notification] - the sender should be invited
        3. Use ISO 8601 format for times: YYYY-MM-DDTHH:MM:SS
        4. If time is vague, pick a reasonable default based on current time
        5. Event title should be concise and descriptive

        ═══════════════════════════════════════════════════════
        CUSTOM RULES (USER-DEFINED CONTACTS & PREFERENCES):
        ═══════════════════════════════════════════════════════

        [Person - Piotr]
        • Email: piotrekpasztor@gmail.com
        • When scheduling with Piotr, use his email for the invite

        ═══════════════════════════════════════════════════════

        RESPOND WITH VALID JSON:
        {
            "should_create_event": true,
            "inferred_task": "description of the meeting/event",
            "confidence": 0.0-1.0,
            "value_added_context_used": ["list of context items used"],
            "event_title": "Meeting title",
            "start_time": "YYYY-MM-DDTHH:MM:SS",
            "end_time": "YYYY-MM-DDTHH:MM:SS",
            "location": "location or null",
            "notes": "event notes/description or null",
            "attendee_email": "email of person to invite or null",
            "attendee_name": "name of person to invite or null",
            "missing_info": null
        }
        """
    }

    // MARK: - LLM Composition

    private func composeWithLLM(prompt: String) async -> CalendarEventPayload? {
        guard await llmClient.isConfigured else {
            print("📅 ❌ LLM not configured")
            return nil
        }

        let systemPrompt = """
        You are a calendar event assistant. Your job is to parse meeting requests and create calendar events.

        ⚠️ CRITICAL - NOTIFICATION PRIORITY:
        [Notification] context is your #1 source of truth! These contain the actual meeting requests.
        Extract the sender's info - they should be the attendee.

        RULES:
        1. ALWAYS set should_create_event=true for any meeting/calendar intent
        2. Use ISO 8601 format for all times: YYYY-MM-DDTHH:MM:SS
        3. Extract attendee email from context or use known contacts
        4. Make reasonable time assumptions if not specified
        5. Keep event titles concise but descriptive

        EXAMPLE 1 (Chat request from notification):
        Context: [Notification] from Discord, tuso: "hey let's chat today about the new feature"
        Current time: 2025-11-30T14:00:00
        Response:
        {
            "should_create_event": true,
            "event_title": "Chat with Tuso",
            "start_time": "2025-11-30T15:00:00",
            "end_time": "2025-11-30T15:30:00",
            "attendee_name": "Tuso",
            "attendee_email": null,
            "notes": "Discuss new feature"
        }

        EXAMPLE 2 (Meeting with known contact):
        Context: [Notification] from Slack: "Piotr wants to meet tomorrow for coffee"
        Current time: 2025-11-30T10:00:00
        Response:
        {
            "should_create_event": true,
            "event_title": "Coffee with Piotr",
            "start_time": "2025-12-01T10:00:00",
            "end_time": "2025-12-01T10:30:00",
            "attendee_name": "Piotr",
            "attendee_email": "piotrekpasztor@gmail.com",
            "notes": "Coffee chat"
        }

        Respond ONLY with valid JSON.
        """

        print("📅 SYSTEM PROMPT:")
        print("📅 ───────────────────────────────────────────────────")
        print(systemPrompt)
        print("📅 ───────────────────────────────────────────────────")
        print("📅 ═══════════════════════════════════════════════════")
        print("")

        do {
            let response = try await llmClient.callAPI(
                systemPrompt: systemPrompt,
                userMessage: prompt
            )

            // Log the AI response
            print("")
            print("📅 ═══════════════════════════════════════════════════")
            print("📅 AI MODEL RESPONSE:")
            print("📅 ═══════════════════════════════════════════════════")
            print(response)
            print("📅 ═══════════════════════════════════════════════════")
            print("")

            return parseCalendarEventResponse(response)
        } catch {
            print("📅 ❌ LLM error: \(error)")
            return nil
        }
    }

    private func parseCalendarEventResponse(_ response: String) -> CalendarEventPayload? {
        // Extract JSON from response
        var jsonString = response

        // Try to find JSON block safely
        if let startRange = response.range(of: "{"),
           let endRange = response.range(of: "}", options: .backwards) {
            let startIndex = startRange.lowerBound
            let endIndex = endRange.upperBound
            if startIndex < endIndex {
                jsonString = String(response[startIndex..<endIndex])
            }
        }

        // Parse JSON
        guard let data = jsonString.data(using: .utf8) else {
            print("📅 ❌ Failed to encode response as data")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let event = try decoder.decode(CalendarEventPayload.self, from: data)
            return event
        } catch {
            print("📅 ❌ JSON parse error: \(error)")
            return nil
        }
    }
}
