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
    @State private var showReprocessConfirmation = false
    @State private var isReprocessing = false
    @State private var reprocessingProgress = ""
    @State private var showBatchSelection = false
    @State private var refreshTimer: Timer?
    
    private let storageManager = StorageManager.shared
    private let analysisManager = AnalysisManager.shared
    
    var body: some View {
        ZStack {
            // Clean background
            Color(hex: "#FFFBF0")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HeaderView(selectedDate: $selectedDate, showDatePicker: $showDatePicker, showReprocessConfirmation: $showReprocessConfirmation)
                    .padding(.horizontal, 60)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                
                // Timeline content
                ScrollView {
                    TimelineContent(
                        activities: activities,
                        expandedActivity: $expandedActivity
                    )
                    .padding(.horizontal, 60)
                    .padding(.vertical, 20)
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
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
        .onChange(of: selectedDate) { _ in
            loadActivities()
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $selectedDate, isPresented: $showDatePicker)
        }
        .alert("Rerun Analysis", isPresented: $showReprocessConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Select Batches") {
                showBatchSelection = true
            }
            Button("Rerun All", role: .destructive) {
                rerunAnalysis()
            }
        } message: {
            Text("This will delete timeline cards and observations for \(formatDateForDisplay(selectedDate)), then re-transcribe and re-analyze video recordings.\n\nYou can choose to rerun all batches or select specific ones.")
        }
        .sheet(isPresented: $showBatchSelection) {
            BatchSelectionView(
                day: formatDateForStorage(getLogicalDate()),
                analysisManager: analysisManager,
                onCompletion: {
                    loadActivities()
                }
            )
        }
        .overlay {
            if isReprocessing {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                        
                        Text("Reprocessing Day")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        ScrollView {
                            Text(reprocessingProgress)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: 400, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                    }
                    .padding(40)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(16)
                    .shadow(radius: 10)
                }
            }
        }
    }
    
    // MARK: - Timer Management
    private func startRefreshTimer() {
        // Refresh every 60 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            loadActivities()
        }
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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
        
        guard let hour = timeComponents.hour,
              let minute = timeComponents.minute else { return nil }
        
        // Create the date with the parsed time
        var result = calendar.date(bySettingHour: hour,
                                  minute: minute,
                                  second: 0,
                                  of: baseDate) ?? baseDate
        
        // Handle day boundary - if the hour is less than 4 AM, it might belong to the next day
        if hour < 4 {
            // Check if we should add a day
            let baseDateHour = calendar.component(.hour, from: baseDate)
            if baseDateHour >= 4 {
                // Base date is after 4 AM but parsed time is before 4 AM, so add a day
                result = calendar.date(byAdding: .day, value: 1, to: result) ?? result
            }
        }
        
        return result
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
    
    private func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        
        // Adjust for 4 AM boundary
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let displayDate = hour < 4 ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
        
        return formatter.string(from: displayDate)
    }
    
    private func getLogicalDate() -> Date {
        var logicalDate = selectedDate
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selectedDate)
        
        if hour < 4 {
            logicalDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        }
        
        return logicalDate
    }
    
    private func formatDateForStorage(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func rerunAnalysis() {
        isReprocessing = true
        reprocessingProgress = "Starting..."
        
        // Calculate the logical day string
        var logicalDate = selectedDate
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selectedDate)
        
        if hour < 4 {
            logicalDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dayString = formatter.string(from: logicalDate)
        
        analysisManager.reprocessDay(dayString, progressHandler: { progress in
            DispatchQueue.main.async {
                self.reprocessingProgress = progress
            }
        }) { result in
            DispatchQueue.main.async {
                self.isReprocessing = false
                self.reprocessingProgress = ""
                
                switch result {
                case .success:
                    // Reload the activities after successful reprocessing
                    self.loadActivities()
                case .failure(let error):
                    // Show error alert
                    print("Reprocessing failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Header View
struct HeaderView: View {
    @Binding var selectedDate: Date
    @Binding var showDatePicker: Bool
    @Binding var showReprocessConfirmation: Bool
    
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
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Color(hex: "#1A1A1A"))
            
            Spacer()
            
            HStack(spacing: 12) {
                // Date picker button
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14))
                    Text(dateFormatter.string(from: displayDate))
                        .font(.system(size: 16, weight: .regular))
                }
                .foregroundColor(Color(hex: "#4A4A4A"))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "#E0E0E0"), lineWidth: 1)
                )
                .cornerRadius(6)
                .onTapGesture {
                    showDatePicker = true
                }
                
                // Rerun analysis button
                Button(action: {
                    showReprocessConfirmation = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                        Text("Rerun Analysis")
                            .font(.system(size: 14, weight: .regular))
                    }
                    .foregroundColor(Color(hex: "#666666"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: "#E0E0E0"), lineWidth: 1)
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
    }
}

// MARK: - Timeline Content
struct TimelineContent: View {
    let activities: [TimelineActivity]
    @Binding var expandedActivity: TimelineActivity?
    
    // Calculate gap in pixels based on time difference
    private func gapHeight(between current: TimelineActivity, and next: TimelineActivity) -> CGFloat {
        let timeDiff = next.startTime.timeIntervalSince(current.endTime) / 60 // minutes
        
        // No gap if activities are adjacent (less than 15 minutes)
        if timeDiff < 15 {
            return 0
        }
        
        // Base gap of 20px for 15 minutes, then 2px per additional minute
        let baseGap: CGFloat = 20
        let additionalMinutes = timeDiff - 15
        let pixelsPerMinute: CGFloat = 2
        
        // Cap the maximum gap at 100px (about 1 hour gap)
        return min(baseGap + (additionalMinutes * pixelsPerMinute), 100)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                TimelineRow(
                    activity: activity,
                    isExpanded: expandedActivity?.id == activity.id,
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedActivity?.id == activity.id {
                                expandedActivity = nil
                            } else {
                                expandedActivity = activity
                            }
                        }
                    },
                    isLast: index == activities.count - 1
                )
                
                // Add gap if there's a time gap to the next activity
                if index < activities.count - 1 {
                    let gap = gapHeight(between: activity, and: activities[index + 1])
                    if gap > 0 {
                        Spacer()
                            .frame(height: gap)
                    }
                }
            }
        }
    }
}

// MARK: - Timeline Row
struct TimelineRow: View {
    let activity: TimelineActivity
    let isExpanded: Bool
    let onTap: () -> Void
    let isLast: Bool
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }
    
    private var duration: TimeInterval {
        activity.endTime.timeIntervalSince(activity.startTime)
    }
    
    private var durationInMinutes: Int {
        Int(duration / 60)
    }
    
    private var cardHeight: CGFloat {
        // Base height: 100px for 15 min, +2.67px per additional minute
        let baseHeight: CGFloat = 100
        let additionalHeight = CGFloat(max(0, durationInMinutes - 15)) * 2.67
        let calculatedHeight = baseHeight + additionalHeight
        // Cap at 300px for very long sessions
        return min(300, max(80, calculatedHeight))
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Time label and dot
            HStack(alignment: .top, spacing: 8) {
                Text(timeFormatter.string(from: activity.startTime))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#666666"))
                    .frame(width: 60, alignment: .trailing)
                
                ZStack {
                    // Timeline line behind the dot - now using dotted pattern
                    if !isLast {
                        GeometryReader { geometry in
                            Path { path in
                                let dashHeight: CGFloat = 3
                                let dashSpacing: CGFloat = 5
                                var currentY: CGFloat = 12
                                
                                while currentY < geometry.size.height {
                                    path.move(to: CGPoint(x: 0.5, y: currentY))
                                    path.addLine(to: CGPoint(x: 0.5, y: currentY + dashHeight))
                                    currentY += dashHeight + dashSpacing
                                }
                            }
                            .stroke(Color(hex: "#CCCCCC"), lineWidth: 1.5)
                        }
                        .frame(width: 2)
                    }
                    
                    // Timeline dot
                    Circle()
                        .fill(Color(hex: "#333333"))
                        .frame(width: 10, height: 10)
                        .zIndex(1)
                }
                .frame(width: 10)
            }
            
            // Activity card
            TimelineActivityCard(
                activity: activity,
                isExpanded: isExpanded,
                cardHeight: cardHeight,
                durationInMinutes: durationInMinutes,
                onTap: onTap
            )
            .padding(.leading, 20)
        }
        .padding(.bottom, isExpanded ? 20 : 8)
    }
}

// MARK: - Timeline Activity Card
struct TimelineActivityCard: View {
    let activity: TimelineActivity
    let isExpanded: Bool
    let cardHeight: CGFloat
    let durationInMinutes: Int
    let onTap: () -> Void
    
    // Category gradient colors
    private func gradientColors(for category: String) -> [Color] {
        switch category.lowercased() {
        case "productive work", "work", "research", "coding", "writing":
            return [Color(hex: "FFFEFE"), Color(hex: "D9F2FB")]
        case "personal", "social", "communication":
            return [Color(hex: "FFFFFF"), Color(hex: "F0E6FF")]
        case "distraction", "entertainment":
            return [Color(hex: "FFFFFF"), Color(hex: "FFE8E8")]
        case "learning", "education":
            return [Color(hex: "FFFFFF"), Color(hex: "FFF4E8")]
        case "idle", "break":
            return [Color(hex: "FFFFFF"), Color(hex: "F8F5F8")]
        default:
            return [Color(hex: "FFFFFF"), Color(hex: "F5F5F5")]
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                // Time range
                Text(formatTimeRange(start: activity.startTime, end: activity.endTime))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.black.opacity(0.6))
                
                // Category badge
                Text(activity.category)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.5))
                    .cornerRadius(8)
                
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
            
            Text(activity.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color(hex: "1A1A1A"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            
            if !isExpanded && !activity.summary.isEmpty {
                Text(activity.summary)
                    .font(.system(size: 14))
                    .foregroundColor(.black.opacity(0.7))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(activity.summary)
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
        .padding(14)
        .frame(height: isExpanded ? nil : cardHeight)
        .frame(maxWidth: 600)
        .background(
            ZStack {
                // Gradient background
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors(for: activity.category)),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Diagonal pattern for distractions
                if activity.category.lowercased() == "distraction" || activity.category.lowercased() == "entertainment" {
                    DiagonalPatternFill()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
        .onTapGesture(perform: onTap)
    }
    
    private func formatTimeRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        let startStr = formatter.string(from: start)
        let endStr = formatter.string(from: end)
        
        return "\(startStr) - \(endStr)"
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