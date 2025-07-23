//
//  TimelineViewV2.swift
//  Dayflow
//
//  Created by Jerry Liu on 2025-01-23.
//

import SwiftUI

struct TimelineViewV2: View {
    @State private var selectedFilter = "All tasks"
    
    var body: some View {
        ZStack {
            // Step 1: Background color
            Color(hex: "FFFBF0")
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                // Step 2: Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterPill(emoji: "📋", text: "All tasks", isSelected: selectedFilter == "All tasks") {
                            selectedFilter = "All tasks"
                        }
                        FilterPill(emoji: "👷", text: "Core tasks", isSelected: selectedFilter == "Core tasks") {
                            selectedFilter = "Core tasks"
                        }
                        FilterPill(emoji: "👀", text: "Personal tasks", isSelected: selectedFilter == "Personal tasks") {
                            selectedFilter = "Personal tasks"
                        }
                        FilterPill(emoji: "😐", text: "Distractions", isSelected: selectedFilter == "Distractions") {
                            selectedFilter = "Distractions"
                        }
                        FilterPill(emoji: "😴", text: "Idle time", isSelected: selectedFilter == "Idle time") {
                            selectedFilter = "Idle time"
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 30)
                    .padding(.bottom, 25)
                }
                
                // Step 3: Timeline Content
                ScrollView {
                    TimelineContentV2()
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - Filter Pill
struct FilterPill: View {
    let emoji: String
    let text: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emoji)
                    .font(.system(size: 16))
                Text(text)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isSelected {
                        LinearGradient(
                            gradient: Gradient(colors: [Color(hex: "FFD4A5"), Color(hex: "FFEDC9")]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        LinearGradient(
                            gradient: Gradient(colors: pillGradientColors),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            )
            .foregroundColor(isSelected ? Color(hex: "8B6914") : Color(hex: "555555"))
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(isSelected ? 0.1 : 0.05), radius: 3, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color(hex: "D4AF37").opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var pillGradientColors: [Color] {
        switch text {
        case "Core tasks":
            return [Color(hex: "D6E9FF"), Color(hex: "F0F7FF")]
        case "Personal tasks":
            return [Color(hex: "E6D9FF"), Color(hex: "F5F0FF")]
        case "Distractions":
            return [Color(hex: "FFD6D6"), Color(hex: "FFF0F0")]
        case "Idle time":
            return [Color(hex: "FFE6D6"), Color(hex: "FFF5F0")]
        default:
            return [Color(hex: "FFD4A5"), Color(hex: "FFEDC9")]
        }
    }
}

// MARK: - Timeline Content
struct TimelineContentV2: View {
    let activities = [
        (time: "5:00 PM", activity: ActivityData(icon: "🤖", domain: "claude.ai", title: "Researching with Claude", timeRange: "5:00PM to 6:30PM", category: .research, duration: 90)),
        (time: "6:30 PM", activity: ActivityData(icon: "✈️", domain: "www.google.com/chrome", title: "Comparing flight prices", timeRange: nil, category: .personal, duration: 15)),
        (time: "6:45 PM", activity: ActivityData(icon: "𝕏", domain: "twitter.com", title: "Browsing Twitter", timeRange: nil, category: .distraction, duration: 10)),
        (time: "6:55 PM", activity: ActivityData(icon: "▶️", domain: "youtube.com", title: "Youtube for content", timeRange: "6:55PM to 7:21PM", category: .personal, duration: 26)),
        (time: "7:21 PM", activity: ActivityData(icon: "😴", domain: nil, title: "Idle time", timeRange: "7:21PM to 7:30PM", category: .idle, duration: 9)),
        (time: "7:30 PM", activity: ActivityData(icon: "📋", domain: nil, title: "Identifying the task...", timeRange: nil, category: .work, duration: 15))
    ]
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dotted line
            DottedLine()
                .offset(x: 80, y: 5)
            
            // Rows
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(activities.enumerated()), id: \.offset) { index, item in
                    TimelineRowV2(
                        time: item.time,
                        activity: item.activity,
                        isLast: index == activities.count - 1
                    )
                }
            }
        }
    }
}

struct ActivityData {
    let icon: String
    let domain: String?
    let title: String
    let timeRange: String?
    let category: ActivityCategory
    let duration: Int // in minutes
    
    enum ActivityCategory {
        case research, personal, distraction, work, idle
        
        var backgroundColor: Color {
            switch self {
            case .research: return Color(hex: "F0F7FF")
            case .personal: return Color(hex: "F5F0FF")
            case .distraction: return Color(hex: "FFF0F0")
            case .work: return Color(hex: "FFF8F0")
            case .idle: return Color(hex: "F8F0FF")
            }
        }
        
        var gradientColors: [Color] {
            switch self {
            case .research: return [Color(hex: "FFFEFE"), Color(hex: "D9F2FB")]
            case .personal: return [Color(hex: "FFFFFF"), Color(hex: "F0E6FF")]
            case .distraction: return [Color(hex: "FFFFFF"), Color(hex: "FFE8E8")]
            case .work: return [Color(hex: "FFFFFF"), Color(hex: "FFF4E8")]
            case .idle: return [Color(hex: "FFFFFF"), Color(hex: "F8F5F8")]
            }
        }
        
        var hasPattern: Bool {
            self == .distraction
        }
    }
}

struct DottedLine: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let dashHeight: CGFloat = 3
                let dashSpacing: CGFloat = 5
                let totalHeight = geometry.size.height
                
                var currentY: CGFloat = 0
                
                while currentY < totalHeight {
                    path.move(to: CGPoint(x: 0, y: currentY))
                    path.addLine(to: CGPoint(x: 0, y: currentY + dashHeight))
                    currentY += dashHeight + dashSpacing
                }
            }
            .stroke(Color(hex: "CCCCCC"), lineWidth: 1.5)
        }
        .frame(width: 1.5)
    }
}

// MARK: - Timeline Row
struct TimelineRowV2: View {
    let time: String
    let activity: ActivityData
    let isLast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            // Time label
            Text(time)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "666666"))
                .frame(width: 70, alignment: .trailing)
            
            // Dot
            Circle()
                .fill(Color(hex: "333333"))
                .frame(width: 10, height: 10)
                .zIndex(1)
            
            // Activity card
            TimelineActivityCardV2(activity: activity)
            
            Spacer()
        }
        .padding(.bottom, isLast ? 0 : 15)
    }
}

// MARK: - Activity Card
struct TimelineActivityCardV2: View {
    let activity: ActivityData
    
    private var cardHeight: CGFloat {
        // Base height of 40px + 2px per minute
        let baseHeight: CGFloat = 40
        let heightPerMinute: CGFloat = 2
        return baseHeight + (CGFloat(activity.duration) * heightPerMinute)
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: activity.category.gradientColors),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Pattern overlay for distractions
            if activity.category.hasPattern {
                DiagonalPatternFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    // Icon
                    if let domain = activity.domain {
                        AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=32")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Text(activity.icon)
                                .font(.system(size: 18))
                        }
                        .frame(width: 20, height: 20)
                    } else {
                        Text(activity.icon)
                            .font(.system(size: 18))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        // Title
                        Text(activity.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "1A1A1A"))
                        
                        // Time range if available
                        if let timeRange = activity.timeRange {
                            Text(timeRange)
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "666666").opacity(0.8))
                        }
                    }
                    
                    Spacer()
                }
                
                Spacer()
            }
            .padding(14)
        }
        .frame(height: cardHeight)
        .frame(maxWidth: 500)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
    }
}

// MARK: - Diagonal Pattern Fill
struct DiagonalPatternFill: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let stripeWidth: CGFloat = 2
                let stripeSpacing: CGFloat = 8
                
                // Draw diagonal stripes (flipped direction - bottom-left to top-right)
                for i in stride(from: -geometry.size.height, to: geometry.size.width + geometry.size.height, by: stripeWidth + stripeSpacing) {
                    path.move(to: CGPoint(x: i, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: i + geometry.size.height, y: 0))
                    path.addLine(to: CGPoint(x: i + geometry.size.height + stripeWidth, y: 0))
                    path.addLine(to: CGPoint(x: i + stripeWidth, y: geometry.size.height))
                    path.closeSubpath()
                }
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(hex: "FFA0A0").opacity(0), location: 0),
                        .init(color: Color(hex: "FFA0A0").opacity(0), location: 0.33),
                        .init(color: Color(hex: "FFA0A0").opacity(0.15), location: 0.5),
                        .init(color: Color(hex: "FFA0A0").opacity(0.3), location: 0.75),
                        .init(color: Color(hex: "FFA0A0").opacity(0.4), location: 1)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

// MARK: - Preview
struct TimelineViewV2_Previews: PreviewProvider {
    static var previews: some View {
        TimelineViewV2()
            .frame(width: 800, height: 600)
    }
}
