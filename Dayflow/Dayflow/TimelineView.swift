//
//  TimelineView.swift
//  Dayflow
//
//  Created by Jerry Liu on 4/20/25.
//

import SwiftUI
import AVFoundation

// MARK: - Data Models
struct TimelineActivity: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let title: String
    let summary: String
    let detailedSummary: String
    let category: String
    let subcategory: String
    let distractions: [Distraction]?
    let videoSummaryURL: String?
    let screenshot: NSImage?
}

// MARK: - Timeline View
struct TimelineView: View {
    @State private var selectedDate = Date()
    @State private var activities: [TimelineActivity] = []
    @State private var expandedActivity: TimelineActivity?
    @State private var isLoading = false
    @State private var showDatePicker = false
    
    private let storageManager = StorageManager.shared
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color(hex: "#FFE5B4"), Color(hex: "#FFB347")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HeaderView(selectedDate: $selectedDate, showDatePicker: $showDatePicker)
                    .padding(.horizontal, 40)
                    .padding(.top, 30)
                
                // Timeline content
                ScrollView {
                    TimelineContent(
                        activities: activities,
                        expandedActivity: $expandedActivity
                    )
                    .padding(.horizontal, 40)
                    .padding(.vertical, 30)
                }
                
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
        }
        .onAppear {
            loadActivities()
        }
        .onChange(of: selectedDate) { _ in
            loadActivities()
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $selectedDate, isPresented: $showDatePicker)
        }
    }
    
    // MARK: - Data Loading
    private func loadActivities() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Adjust for 4 AM boundary - if it's before 4 AM, we want yesterday's logical day
            var logicalDate = selectedDate
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: selectedDate)
            
            if hour < 4 {
                // It's after midnight but before 4 AM, so this belongs to yesterday's logical day
                logicalDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dayString = formatter.string(from: logicalDate)
            
            let timelineCards = storageManager.fetchTimelineCards(forDay: dayString)
            let activities = processTimelineCards(timelineCards)
            
            DispatchQueue.main.async {
                self.activities = activities
                self.isLoading = false
            }
        }
    }
    
    private func processTimelineCards(_ cards: [TimelineCard]) -> [TimelineActivity] {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        var activities: [TimelineActivity] = []
        
        for card in cards {
            // Parse start and end times
            guard let baseDate = dateFormatter.date(from: card.day),
                  let startTime = parseTime(card.startTimestamp, baseDate: baseDate),
                  let endTime = parseTime(card.endTimestamp, baseDate: baseDate) else {
                continue
            }
            
            // Parse distractions from metadata JSON
            var distractions: [Distraction]? = nil
            if let metadataString = card.distractions?.compactMap({ distraction in
                try? JSONEncoder().encode(distraction)
            }).compactMap({ String(data: $0, encoding: .utf8) }).first {
                // Distractions are already parsed in TimelineCard
                distractions = card.distractions
            }
            
            // Load video thumbnail if available
            let screenshot = loadVideoThumbnail(from: card.videoSummaryURL)
            
            let activity = TimelineActivity(
                startTime: startTime,
                endTime: endTime,
                title: card.title,
                summary: card.summary,
                detailedSummary: card.detailedSummary,
                category: card.category,
                subcategory: card.subcategory,
                distractions: distractions,
                videoSummaryURL: card.videoSummaryURL,
                screenshot: screenshot
            )
            
            activities.append(activity)
        }
        
        return activities.sorted { $0.startTime < $1.startTime }
    }
    
    private func parseTime(_ timeString: String, baseDate: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let time = formatter.date(from: timeString) else { return nil }
        
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        
        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
                           minute: timeComponents.minute ?? 0,
                           second: 0,
                           of: baseDate)
    }
    
    private func loadVideoThumbnail(from urlString: String?) -> NSImage? {
        guard let urlString = urlString,
              let url = URL(string: urlString) else { return nil }
        
        // Extract first frame from video
        return extractFrame(from: url, at: 0.5) // Get frame at 0.5 seconds
    }
    
    private func extractFrame(from videoURL: URL, at time: TimeInterval) -> NSImage? {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 1)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: cmTime, actualTime: nil)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            print("Error extracting frame: \(error)")
            return nil
        }
    }
}

// MARK: - Header View
struct HeaderView: View {
    @Binding var selectedDate: Date
    @Binding var showDatePicker: Bool
    
    private var displayDate: Date {
        // Adjust for 4 AM boundary for display
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selectedDate)
        
        if hour < 4 {
            // Show yesterday's date since this is part of yesterday's logical day
            return calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        }
        return selectedDate
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE | MMMM d"
        return formatter
    }
    
    var body: some View {
        HStack {
            Text("Timeline")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Color(hex: "#FF6347"))
            
            Spacer()
            
            HStack(spacing: 15) {
                Image(systemName: "calendar")
                Text(dateFormatter.string(from: displayDate))
                    .font(.system(size: 18, weight: .medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.9))
            .cornerRadius(20)
            .onTapGesture {
                showDatePicker = true
            }
        }
    }
}

// MARK: - Timeline Content
struct TimelineContent: View {
    let activities: [TimelineActivity]
    @Binding var expandedActivity: TimelineActivity?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(activities) { activity in
                TimelineRow(
                    activity: activity,
                    isExpanded: expandedActivity?.id == activity.id,
                    onTap: {
                        withAnimation(.spring()) {
                            if expandedActivity?.id == activity.id {
                                expandedActivity = nil
                            } else {
                                expandedActivity = activity
                            }
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Timeline Row
struct TimelineRow: View {
    let activity: TimelineActivity
    let isExpanded: Bool
    let onTap: () -> Void
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Time label
            VStack(alignment: .trailing, spacing: 5) {
                Text(timeFormatter.string(from: activity.startTime))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.black.opacity(0.8))
                
                // Timeline indicator
                Circle()
                    .fill(Color.black)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
            }
            .frame(width: 80)
            
            // Activity card
            VStack(alignment: .leading, spacing: 0) {
                TimelineActivityCard(
                    activity: activity,
                    isExpanded: isExpanded,
                    onTap: onTap
                )
                
                // Timeline line
                if !isExpanded {
                    Rectangle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 2)
                        .frame(minHeight: 50)
                        .padding(.leading, 40)
                }
            }
        }
    }
}

// MARK: - Timeline Activity Card
struct TimelineActivityCard: View {
    let activity: TimelineActivity
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                // Category badge
                Text(activity.category)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.5))
                    .cornerRadius(8)
                
                Text(activity.title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.black.opacity(0.9))
                
                Spacer()
                
                if isExpanded {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black.opacity(0.6))
                        .padding(8)
                        .background(Color.white.opacity(0.3))
                        .cornerRadius(8)
                }
            }
            
            if !isExpanded && !activity.summary.isEmpty {
                Text(activity.summary)
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.7))
                    .lineLimit(2)
                    .padding(.top, 4)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(activity.detailedSummary)
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.8))
                    
                    if let distractions = activity.distractions, !distractions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Other activities:")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.black.opacity(0.6))
                            
                            ForEach(distractions, id: \.id) { distraction in
                                HStack {
                                    Text("• \(distraction.title)")
                                        .font(.system(size: 12))
                                    Text("(\(distraction.startTime) - \(distraction.endTime))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.black.opacity(0.5))
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    if let screenshot = activity.screenshot {
                        Image(nsImage: screenshot)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .shadow(radius: 5)
                    }
                }
                .padding(.top, 5)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.95))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        .onTapGesture(perform: onTap)
        .overlay(
            HStack {
                Spacer()
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 24))
                    .foregroundColor(.black.opacity(0.8))
                    .offset(x: 30, y: 30)
            }
            .opacity(isExpanded ? 0 : 1)
            .animation(.easeInOut, value: isExpanded)
        )
    }
}

// MARK: - Date Picker Sheet
struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select Date")
                .font(.title2)
                .padding(.top)
            
            DatePicker(
                "Date",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(GraphicalDatePickerStyle())
            .labelsHidden()
            .padding()
            
            HStack {
                Button("Today") {
                    selectedDate = Date()
                }
                .keyboardShortcut(.defaultAction)
                
                Spacer()
                
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 400, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}