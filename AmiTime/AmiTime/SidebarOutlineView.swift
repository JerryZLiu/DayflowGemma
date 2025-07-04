//
//  SidebarOutlineView.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/20/25.
//

import SwiftUI

// MARK: - SidebarOutlineView

/// Left‑hand outline listing Subjects and their Tasks.
/// Custom implementation (no DisclosureGroup) so we can fine‑tune paddings, fonts, hover, and dividers.
struct SidebarOutlineView: View {

    // Eventually this will come from Core Data; for now sample data.
    @State private var subjects: [Subject] = PreviewData.subjects

    /// Design tokens for easy tweaking.
    enum Style {
        // Fonts
        static let subjectFont  = Font.system(size: 16, weight: .medium)
        static let taskFont     = Font.system(size: 14)
        static let timeFont     = Font.system(size: 14)
        static let headerFont   = Font.system(size: 14, weight: .medium)

        // Colors
        static let subjectColor = Color.black
        static let taskColor    = Color.gray
        static let timeColor    = Color.gray
        static let dividerColor = Color.gray.opacity(0.1)
        static let headerColor  = Color.gray

        // Insets - adjusted for exact match
        static let subjectInsets = EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        static let taskInsets    = EdgeInsets(top: 12, leading: 48, bottom: 12, trailing: 20)

        // Hover
        static let hoverColor = Color.gray.opacity(0.03)
    }

    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h:mm"
        return df
    }()

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SUBJECTS")
                        .font(Style.headerFont)
                        .foregroundColor(Style.headerColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .frame(width: geometry.size.width)
                    
                    Divider()
                        .foregroundColor(Style.dividerColor)
                        
                    // This fixes animation with LazyVStack
                    let _ = print("Force refresh for animation")
                    
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach($subjects) { $subject in
                            // SUBJECT ROW (taps to collapse/expand)
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    subject.isExpanded.toggle()
                                }
                            } label: {
                                SubjectRow(subject: subject)
                            }
                            .buttonStyle(.plain) // keep custom look
                            .sidebarRowStyle(isSubject: true)
                            .frame(width: geometry.size.width)

                            // TASK ROWS (conditionally shown with animation)
                            if subject.isExpanded {
                                ForEach(Array(subject.tasks.enumerated()), id: \.element.id) { idx, task in
                                    TaskRow(index: idx + 1, task: task)
                                        .sidebarRowStyle(isSubject: false)
                                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                                        .frame(width: geometry.size.width)
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollContentBackground(.hidden)
            .background(Color(.white))
        }
    }

    // MARK: - Row views

    private struct SubjectRow: View {
        let subject: Subject
        @Environment(\.isFocused) private var isFocused // preserve default focus ring

        var body: some View {
            HStack(spacing: 8) {
                Text(subject.name)
                    .font(Style.subjectFont)
                    .foregroundColor(Style.subjectColor)
                    .lineLimit(1)

                Spacer()

                // Chevron
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(subject.isExpanded ? 0 : -90))
                    .foregroundColor(Style.subjectColor.opacity(0.5))
                    .font(.system(size: 8, weight: .semibold))
                    .animation(.easeInOut(duration: 0.2), value: subject.isExpanded)
            }
        }
    }

    private struct TaskRow: View {
        let index: Int
        let task: Task
        @Environment(\.colorScheme) private var colorScheme
        private let timeFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "h:mm"
            return df
        }()

        var body: some View {
            HStack(spacing: 8) {
                Text(task.title)
                    .font(Style.taskFont)
                    .foregroundColor(Style.taskColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(timeFormatter.string(from: task.start))
                    .font(Style.timeFont)
                    .foregroundColor(Style.timeColor)
            }
        }
    }
}

// MARK: - Row Style Modifier
private struct SidebarRowStyle: ViewModifier {
    let isSubject: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(isHovering ? SidebarOutlineView.Style.hoverColor : Color.clear)
            .padding(isSubject ? SidebarOutlineView.Style.subjectInsets
                              : SidebarOutlineView.Style.taskInsets)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .overlay(
                isSubject ? AnyView(
                    Rectangle()
                        .fill(SidebarOutlineView.Style.dividerColor)
                        .frame(height: 1)
                        .padding(.horizontal, 0)
                ) : AnyView(EmptyView()),
                alignment: .bottom
            )
    }
}

private extension View {
    func sidebarRowStyle(isSubject: Bool) -> some View {
        modifier(SidebarRowStyle(isSubject: isSubject))
    }
}

// MARK: - Preview
struct SidebarOutlineView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarOutlineView()
            .frame(width: 500, height: 500)
            .previewDisplayName("Sidebar Outline ‑ polished")
    }
}
