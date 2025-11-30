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
        print("")
        print("📅 ═══════════════════════════════════════════════════")
        print("📅 CalendarHelper.createEvent(from payload:) CALLED")
        print("📅 ═══════════════════════════════════════════════════")
        print("📅 Payload details:")
        print("📅   shouldCreateEvent: \(payload.shouldCreateEvent)")
        print("📅   eventTitle: \(payload.eventTitle)")
        print("📅   startTime (raw): \(payload.startTime)")
        print("📅   endTime (raw): \(payload.endTime)")
        print("📅   attendeeEmail: \(payload.attendeeEmail ?? "nil")")
        print("📅   attendeeName: \(payload.attendeeName ?? "nil")")
        print("📅   location: \(payload.location ?? "nil")")
        print("📅   notes: \(payload.notes ?? "nil")")
        print("📅   isActionable: \(payload.isActionable)")

        guard let startDate = payload.startDate else {
            print("📅 ❌ Cannot create event: FAILED to parse start time from '\(payload.startTime)'")
            print("📅 ❌ Make sure the LLM returns ISO 8601 format: YYYY-MM-DDTHH:MM:SS")
            return
        }
        print("📅 ✅ startDate parsed: \(startDate)")

        let endDate = payload.endDate ?? startDate.addingTimeInterval(3600) // Default 1 hour
        if payload.endDate == nil {
            print("📅 ⚠️ endDate not parsed, using default +1 hour: \(endDate)")
        } else {
            print("📅 ✅ endDate parsed: \(endDate)")
        }

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
        print("")
        print("📅 ═══════════════════════════════════════════════════")
        print("📅 RUNNING APPLESCRIPT")
        print("📅 ═══════════════════════════════════════════════════")
        print("📅 Script:")
        print(script)
        print("📅 ───────────────────────────────────────────────────")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        do {
            try task.run()
            task.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            if let stdout = String(data: stdoutData, encoding: .utf8), !stdout.isEmpty {
                print("📅 osascript stdout: \(stdout)")
            }

            if let stderr = String(data: stderrData, encoding: .utf8), !stderr.isEmpty {
                print("📅 ⚠️ osascript stderr: \(stderr)")
            }

            if task.terminationStatus != 0 {
                print("📅 ❌ osascript failed with exit code: \(task.terminationStatus)")
                print("📅 ❌ Common issues:")
                print("📅     - Calendar app not accessible")
                print("📅     - Calendar '\(script.contains("szymon.rybczak@gmail.com") ? "szymon.rybczak@gmail.com" : "unknown")' does not exist")
                print("📅     - Automation permissions not granted")
            } else {
                print("📅 ✅ Calendar event created successfully!")
            }
        } catch {
            print("📅 ❌ Failed to run osascript: \(error)")
            print("📅 ❌ This usually means:")
            print("📅     - /usr/bin/osascript not found")
            print("📅     - Process execution blocked")
        }
        print("📅 ═══════════════════════════════════════════════════")
    }

    private static func escapeForAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
