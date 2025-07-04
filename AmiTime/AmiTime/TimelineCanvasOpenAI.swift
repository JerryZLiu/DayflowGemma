import SwiftUI

/// A lightweight, self‑contained timeline axis that matches the screenshot you shared.
/// ‑ 4 half‑hour ticks starting at `startTime`
/// ‑ dashed grid lines
/// ‑ a red "now" marker (optional)
struct TimelineAxis: View {
    /// The left‑most time shown on the axis.
    let startTime: Date
    /// How many 30‑minute segments to draw (4 → two hours).
    let segments: Int
    /// Width of each segment.
    let segmentWidth: CGFloat
    /// Where to draw the red "now" line. Pass `nil` to hide it.
    let now: Date?

    @State private var pulse = false

    private let minuteStep: TimeInterval = 30 * 60 // 30 min
    private let labelFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h a"
        return df
    }()

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let sectionWidth = segmentWidth

            ZStack(alignment: .topLeading) {
                // Top horizontal line
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: totalWidth, y: 0))
                }
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)

                // Tick marks every 5 min, longer at 15 / 30 / 60 min
                let labelHeight: CGFloat = 18
                ForEach(0...segments, id: \.self) { idx in
                    let x = CGFloat(idx) * sectionWidth   // sectionWidth == width per 5 min
                    let minutes = idx * 5
                    let isHour   = minutes % 60 == 0
                    let isHalf   = minutes % 30 == 0
                    let isQuarter = minutes % 15 == 0

                    // A 1×1 invisible view so ScrollViewReader can scroll to this index
                    Color.clear
                        .frame(width: 1, height: 1)
                        .id("segment-\(idx)")
                        .position(x: x, y: 0)

                    // tick length by type – cut to one‑third again (extra subtle)
                    let full = geo.size.height
                    let tickLen: CGFloat = isHour ? full * 0.044   // ≈4 %
                                     : isHalf ? full * 0.031       // ≈3 %
                                     : isQuarter ? full * 0.020    // 2 %
                                     : full * 0.011                // 1 %

                    // main tick
                    Path { p in
                        p.move(to: CGPoint(x: x, y: labelHeight))
                        p.addLine(to: CGPoint(x: x, y: labelHeight + tickLen))
                    }
                    .stroke(Color.secondary.opacity(isHour ? 0.3 : 0.15), lineWidth: 1)

                    // time label only on the hour
                    if isHour {
                        let labelDate = startTime.addingTimeInterval(Double(minutes) * 60)
                        Text(labelFormatter.string(from: labelDate))
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                            .frame(width: 40)
                            .position(x: x, y: labelHeight / 2)
                    }
                }

                // Pulsing "now" marker
                if let nowDate = now {
                    // distance from start in minutes
                    let minutesFromStart = nowDate.timeIntervalSince(startTime) / 60
                    let offset = CGFloat(minutesFromStart / 5) * sectionWidth   // one section = 5 min

                    if offset >= 0 && offset <= totalWidth {
                        Rectangle()
                            .fill(Color.red.opacity(0.7))
                            .frame(width: 2, height: geo.size.height)
                            .position(x: offset, y: geo.size.height / 2)
                            .opacity(pulse ? 0.25 : 0.9)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                    pulse.toggle()
                                }
                            }
                    }
                }
            }
        }
    }
}

// Tracks horizontal content offset inside the ScrollView
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: -- Zoom
private enum ZoomLevel: String, CaseIterable, Identifiable {
    case one  = "1 h"
    case four = "4 h"
    case eight = "8 h"

    var id: Self { self }

    /// Number of five‑minute segments visible in the viewport
    var visibleSegments: Int {
        switch self {
        case .one:   return 12       // 60 min / 5 min
        case .four:  return 48       // 240 min / 5 min
        case .eight: return 96       // 480 min / 5 min
        }
    }
}

// MARK: -- Scrollable wrapper
struct DraggableTimelineView: View {
    @State private var zoom: ZoomLevel = .four   // default 4 h view
    @State private var centerIndex: Int = 0   // 5‑min index currently at screen center
    private let startOfDay = Calendar.current.startOfDay(for: Date())
    private let totalSegments = 288         // 24 h / 5‑min segments
    private let now = Date()

    var body: some View {
        VStack(spacing: 8) {
            // Segmented control to pick zoom level
            Picker("Zoom", selection: $zoom) {
                ForEach(ZoomLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            GeometryReader { geo in
                let segmentWidth = geo.size.width / CGFloat(zoom.visibleSegments)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        TimelineAxis(
                            startTime: startOfDay,
                            segments: totalSegments,
                            segmentWidth: segmentWidth,
                            now: now
                        )
                        // set the explicit frame so the axis knows its full width
                        .frame(width: segmentWidth * CGFloat(totalSegments))
                        // GeometryReader to observe the content X offset
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: ScrollOffsetKey.self,
                                    value: g.frame(in: .named("timelineScroll")).minX
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "timelineScroll")
                    .animation(.easeInOut(duration: 0.35), value: zoom)
                    .onAppear {
                        scrollToIndex(Int(now.timeIntervalSince(startOfDay) / 300), proxy: proxy, animated: false)
                    }
                    .onChange(of: zoom) { _ in
                        scrollToIndex(centerIndex, proxy: proxy, animated: true)
                    }
                    .onPreferenceChange(ScrollOffsetKey.self) { minX in
                        // minX is negative when scrolled right; convert to positive offset
                        let contentOffset = -minX
                        // index at the center of the screen
                        let idx = Int(round((contentOffset + geo.size.width / 2) / segmentWidth))
                        centerIndex = max(0, min(totalSegments, idx))
                    }
                }
            }
        }
    }

    private func scrollToIndex(_ idx: Int, proxy: ScrollViewProxy, animated: Bool) {
        let clamped = max(0, min(totalSegments, idx))
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                proxy.scrollTo("segment-\(clamped)", anchor: .center)
            }
        } else {
            proxy.scrollTo("segment-\(clamped)", anchor: .center)
        }
        centerIndex = clamped
    }
}

// MARK: ‑‑ Preview
struct TimelineAxis_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 0) {
            SidebarOutlineView()
            Divider()
            DraggableTimelineView()
        }
        .frame(maxHeight: .infinity)
        .background(Color(.white))
    }
}
