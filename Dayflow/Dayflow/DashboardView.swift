//
//  DashboardView.swift
//  Dayflow
//
//  Dashboard view with todo list and analytics cards for personal tracking
//

import SwiftUI

// MARK: - Data Models

enum CardType: String, Codable, CaseIterable {
    case count = "Count"
    case time = "Time"
    
    var icon: String {
        switch self {
        case .count: return "number.circle"
        case .time: return "clock"
        }
    }
}

struct DashboardCard: Identifiable, Codable {
    let id = UUID()
    var question: String
    var type: CardType
    var todayValue: Double // For count: number, for time: minutes
    
    var formattedTodayValue: String {
        switch type {
        case .count:
            return "\(Int(todayValue))"
        case .time:
            let hours = Int(todayValue) / 60
            let minutes = Int(todayValue) % 60
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes) min"
            }
        }
    }
    
    var unit: String {
        switch type {
        case .count:
            return "times"
        case .time:
            return ""
        }
    }
}

struct TodoItem: Identifiable, Codable {
    let id = UUID()
    var title: String
    var isCompleted: Bool = false
    var createdDate: Date = Date()
}

// MARK: - Main Dashboard View

struct DashboardView: View {
    @State private var cards: [DashboardCard] = []
    @State private var todos: [TodoItem] = []
    @State private var showingAddCard = false
    @State private var editingCard: DashboardCard?
    @State private var showingAddTodo = false
    @State private var newTodoText = ""
    
    private let maxCards = 6
    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Todo List Section
                todoSection
                
                // Analytics Cards Section
                analyticsSection
            }
            .padding(24)
        }
        .background(Color.white)
        .sheet(isPresented: $showingAddCard) {
            AddCardView { newCard in
                if cards.count < maxCards {
                    cards.append(newCard)
                    saveCards()
                }
            }
        }
        .sheet(item: $editingCard) { card in
            EditCardView(card: card) { updatedCard in
                if let index = cards.firstIndex(where: { $0.id == card.id }) {
                    cards[index] = updatedCard
                    saveCards()
                }
            } onDelete: {
                cards.removeAll { $0.id == card.id }
                saveCards()
            }
        }
        .onAppear {
            loadData()
        }
    }
    
    // MARK: - Todo Section
    
    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's Tasks")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: { showingAddTodo = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            
            if todos.isEmpty {
                Text("No tasks yet. Add one to get started!")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach($todos) { $todo in
                        TodoItemView(todo: $todo) {
                            saveTodos()
                        } onDelete: {
                            todos.removeAll { $0.id == todo.id }
                            saveTodos()
                        }
                    }
                }
            }
            
            if showingAddTodo {
                HStack {
                    TextField("Add a task...", text: $newTodoText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            addNewTodo()
                        }
                    
                    Button("Add") {
                        addNewTodo()
                    }
                    .disabled(newTodoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button("Cancel") {
                        showingAddTodo = false
                        newTodoText = ""
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Analytics Section
    
    private var analyticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personal Analytics")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal)
            
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(cards) { card in
                    AnalyticsCardView(card: card)
                        .onTapGesture {
                            editingCard = card
                        }
                }
                
                if cards.count < maxCards {
                    AddCardButton {
                        showingAddCard = true
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Helper Methods
    
    private func addNewTodo() {
        let trimmedText = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        let newTodo = TodoItem(title: trimmedText)
        todos.append(newTodo)
        saveTodos()
        
        newTodoText = ""
        showingAddTodo = false
    }
    
    private func loadData() {
        // Load cards
        if let cardsData = UserDefaults.standard.data(forKey: "dashboardCards"),
           let decodedCards = try? JSONDecoder().decode([DashboardCard].self, from: cardsData) {
            cards = decodedCards
        } else {
            // Sample data for demo
            cards = [
                DashboardCard(
                    question: "How many times did I check social media?",
                    type: .count,
                    todayValue: 12
                ),
                DashboardCard(
                    question: "How long did I spend in deep work?",
                    type: .time,
                    todayValue: 180
                )
            ]
        }
        
        // Load todos
        if let todosData = UserDefaults.standard.data(forKey: "dashboardTodos"),
           let decodedTodos = try? JSONDecoder().decode([TodoItem].self, from: todosData) {
            todos = decodedTodos
        }
    }
    
    private func saveCards() {
        if let encoded = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(encoded, forKey: "dashboardCards")
        }
    }
    
    private func saveTodos() {
        if let encoded = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(encoded, forKey: "dashboardTodos")
        }
    }
}

// MARK: - Component Views

struct TodoItemView: View {
    @Binding var todo: TodoItem
    var onToggle: () -> Void
    var onDelete: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                todo.isCompleted.toggle()
                onToggle()
            }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? Color(hex: 0x4CAF50) : Color(hex: 0xE0E0E0))
                    .font(.system(size: 20))
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(todo.title)
                .strikethrough(todo.isCompleted)
                .foregroundColor(todo.isCompleted ? Color.gray : Color.black)
                .font(.system(size: 16))
            
            Spacer()
            
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .foregroundColor(Color.gray)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovering ? Color(hex: 0xF8F8F8) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct AnalyticsCardView: View {
    let card: DashboardCard
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.question)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: 0x6B7280))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(card.formattedTodayValue)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(Color.black)
                    
                    if !card.unit.isEmpty {
                        Text(card.unit)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(Color(hex: 0x9CA3AF))
                    }
                }
            }
            
            Spacer()
        }
        .padding(20)
        .frame(height: 140)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xF9FAFB))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: 0xE5E7EB), lineWidth: 1)
        )
    }
}

struct AddCardButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(Color(hex: 0x3B82F6))
                
                Text("Add Card")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(hex: 0x6B7280))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: 140)
            .background(Color(hex: 0xF9FAFB))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(Color(hex: 0xE5E7EB))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}



// MARK: - Add/Edit Card Views

struct AddCardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var question = ""
    @State private var selectedType: CardType = .count
    let onAdd: (DashboardCard) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Analytics Card")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Question")
                    .font(.headline)
                TextField("e.g., How many times did I check email?", text: $question)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Type")
                    .font(.headline)
                Picker("Type", selection: $selectedType) {
                    ForEach(CardType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.icon)
                            Text(type.rawValue)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Add Card") {
                    let newCard = DashboardCard(
                        question: question,
                        type: selectedType,
                        todayValue: 0
                    )
                    onAdd(newCard)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}

struct EditCardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var question: String
    let card: DashboardCard
    let onSave: (DashboardCard) -> Void
    let onDelete: () -> Void
    
    init(card: DashboardCard, onSave: @escaping (DashboardCard) -> Void, onDelete: @escaping () -> Void) {
        self.card = card
        self._question = State(initialValue: card.question)
        self.onSave = onSave
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Card")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Question")
                    .font(.headline)
                TextField("Question", text: $question)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            Spacer()
            
            HStack {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                
                Button("Save") {
                    var updatedCard = card
                    updatedCard.question = question
                    onSave(updatedCard)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
    }
}

// MARK: - Preview

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
} 