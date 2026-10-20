# NagReminderBar — specification

**Tagline:** Type a quick reminder in plain words and it keeps nudging you every few minutes until you mark it done.

**Category:** Timers & Reminders

**Inspired by (paid):** Due ($14.99 one-time)

**Frameworks:** SwiftUI, AppKit, UserNotifications, Foundation, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does and evidence of demand. Due is a long-running reminder and timer app that is known for fast entry and for auto snooze, which repeats an overdue reminder every few minutes until you complete or reschedule it. The Mac version is sold separately from the iOS app at about 14.99 dollars, has been reviewed repeatedly by MacStories and is also part of the Setapp catalog, which shows lasting demand among people who need reminders that cannot be ignored. Our version focuses on that nagging behavior and fast typing.

Feature set for our clean-room version. A menu bar app with a single text field. Typing phrases such as call the dentist in 20 minutes, submit report tomorrow 9am, or stretch every 2 hours creates a reminder. A small parser built with NSDataDetector for dates plus a hand-written relative-time parser for in N minutes and hours handles input. Each reminder has a title, a due date, an optional repeat interval and an auto snooze interval chosen from 1, 5, 10, 15, 30 or 60 minutes. When a reminder is due, a user notification is delivered with actions Done, Snooze 10 minutes and Tomorrow. Unless acted on, the app re-delivers the notification at the auto snooze interval, up to a configurable cap such as 10 repeats, or without limit if set. Completed reminders move to a short history list.

UI spec. A MenuBarExtra using the window style. The top shows the entry field and a live preview line such as Will remind you Tuesday 9:00 AM. Below is a list grouped into Overdue, Today and Later, each row with a check button, the title, the due time and a context menu for Edit, Snooze, Change nag interval and Delete. A badge on the menu bar icon shows the overdue count. The settings window has default nag interval, maximum repeats, default snooze length, a sound picker from the system sounds, launch at login and a global hotkey for opening the entry field, default Control Option R. Empty state: a friendly line saying nothing is due, with example phrases to type.

Technical approach. Store reminders as Codable JSON in Application Support, loaded at launch. Request notification permission with UNUserNotificationCenter on first use, register a category with the three actions and handle responses in a delegate. For nagging, schedule the next several UNNotificationRequests ahead of time with time interval triggers whenever a reminder becomes overdue or is edited, and cancel them on completion. Also run a lightweight timer inside the app that reconciles the pending requests every minute and when the Mac wakes, observing NSWorkspace didWakeNotification. Use SMAppService for launch at login. Do not touch EventKit so no calendar permission is needed.

Edge cases and error handling. If notifications are denied, show an inline banner with a button that opens the system notification settings and fall back to a floating panel alert. Handle sleep by recomputing overdue items on wake and showing a single catch-up notification instead of a burst. Ambiguous input such as only a time of day picks the next occurrence. Unparseable input keeps the text and asks for a time with a small date picker. Cap the number of pending requests below the system limit of 64 by scheduling only the nearest ones. Keep the code near 500 lines.
