//
//  PreviewData.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/20/25.
//

import Foundation

/// Handy fixtures for previews / prototyping.
enum PreviewData {

    /// Same anchor day reused so times are stable each hot‑reload.
    private static let anchorDay: Date = {
        let cal = Calendar.current
        let now = Date()
        // start at today's 5 PM local
        return cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
    }()

    /// Convenience to build times offset by minutes from anchor.
    private static func time(_ minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: anchorDay)!
    }

    // MARK: Sample subjects & tasks
    static let subjects: [Subject] = [
        Subject(
            name: "Computer Science",
            icon: "laptopcomputer",
            tasks: [
                Task(title: "Research & Brainstorming", start: time(35),  end: time(60)),
                Task(title: "First Draft",              start: time(60),  end: time(90)),
                Task(title: "Presentation Creation",    start: time(90),  end: time(120))
            ]
        ),
        Subject(
            name: "Geography",
            icon: "map",
            tasks: [
                Task(title: "Map Analysis",             start: time(40),  end: time(100))
            ]
        ),
        Subject(
            name: "Mathematics",
            icon: "plus",
            tasks: [
                Task(title: "Research & Brainstorming", start: time(35),  end: time(60)),
                Task(title: "First Draft",              start: time(60),  end: time(90)),
                Task(title: "Presentation Creation",    start: time(90),  end: time(120))
            ]
        ),
        Subject(
            name: "Biology",
            icon: "microscope",
            tasks: [
                Task(title: "Lab Write‑up",             start: time(90),  end: time(150))
            ]
        )
    ]
}
