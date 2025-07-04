//
//  TimelineModel.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/20/25.
//

import Foundation
import SwiftUI   //  needed only for Color; safe to keep for future use

// MARK: - Task
/// A single bar on the timeline.
struct Task: Identifiable, Equatable {
    let id: UUID = UUID()
    var title: String
    var start: Date    // absolute start time
    var end: Date      // absolute end time
}

// MARK: - Subject
/// A collapsible group (row in the outline).
struct Subject: Identifiable {
    let id: UUID = UUID()
    var name: String
    var icon: String          // Emoji or SF‑symbol name
    var tasks: [Task]
    var isExpanded: Bool = true
}
