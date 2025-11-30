//
//  CalendarHelper.swift
//  AxPlayground
//
//  Created on 30/11/2025.
//

import Cocoa

/// Helper for creating calendar events using AppleScript.
struct CalendarHelper {

    /// Opens Calendar.app
    static func openCalendarApp() {
        runOsascript("""
            tell application "Calendar"
                activate
            end tell
        """)
    }

    /// Creates a new calendar event with optional attendee
    static func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        notes: String? = nil,
        attendeeEmail: String? = nil
    ) {
        let cal = Calendar.current

        // Extract date components for AppleScript
        let startComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: startDate)
        let endComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: endDate)

        // Build location and notes properties
        var extraProps = ""
        if let location = location, !location.isEmpty {
            extraProps += ", location:\"\(escapeForAppleScript(location))\""
        }
        if let notes = notes, !notes.isEmpty {
            extraProps += ", description:\"\(escapeForAppleScript(notes))\""
        }

        // Build attendee block if email provided
        var attendeeBlock = ""
        if let email = attendeeEmail, !email.isEmpty {
            attendeeBlock = """

                tell newEvent
                    make new attendee at end of attendees with properties {email:"\(escapeForAppleScript(email))"}
                end tell
            """
        }

        let script = """
            tell application "Calendar"
                activate

                set startDate to current date
                set year of startDate to \(startComponents.year ?? 2025)
                set month of startDate to \(startComponents.month ?? 1)
                set day of startDate to \(startComponents.day ?? 1)
                set hours of startDate to \(startComponents.hour ?? 12)
                set minutes of startDate to \(startComponents.minute ?? 0)
                set seconds of startDate to 0

                set endDate to current date
                set year of endDate to \(endComponents.year ?? 2025)
                set month of endDate to \(endComponents.month ?? 1)
                set day of endDate to \(endComponents.day ?? 1)
                set hours of endDate to \(endComponents.hour ?? 13)
                set minutes of endDate to \(endComponents.minute ?? 0)
                set seconds of endDate to 0

                tell calendar "szymon.rybczak@gmail.com"
                    set newEvent to make new event with properties {summary:"\(escapeForAppleScript(title))", start date:startDate, end date:endDate\(extraProps)}
                    \(attendeeBlock)
                end tell
            end tell
        """

        print("📅 Creating calendar event:")
        print("   Title: \(title)")
        print("   Start: \(startDate)")
        print("   End: \(endDate)")
        if let attendeeEmail = attendeeEmail {
            print("   Attendee: \(attendeeEmail)")
        }

        runOsascript(script)
    }

    /// Creates event from CalendarEventPayload
    static func createEvent(from payload: CalendarEventPayload) {
        guard let startDate = payload.startDate else {
            print("📅 ❌ Cannot create event: invalid start time")
            return
        }

        let endDate = payload.endDate ?? startDate.addingTimeInterval(3600) // Default 1 hour

        createEvent(
            title: payload.eventTitle,
            startDate: startDate,
            endDate: endDate,
            location: payload.location,
            notes: payload.notes,
            attendeeEmail: payload.attendeeEmail
        )
    }

    // MARK: - Private Methods

    /// Run AppleScript via osascript command
    private static func runOsascript(_ script: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("📅 osascript output: \(output)")
            }

            if task.terminationStatus != 0 {
                print("❌ osascript failed with status: \(task.terminationStatus)")
            } else {
                print("✅ Calendar event created successfully")
            }
        } catch {
            print("❌ Failed to run osascript: \(error)")
        }
    }

    private static func escapeForAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
