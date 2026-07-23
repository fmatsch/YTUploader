import SwiftUI

/// Ein geplanter Termin eines anderen Auftrags (für die Kalender-Markierung).
struct PlannedEntry {
    let date: Date
    let title: String
}

/// Kleiner Monatskalender für die Zeitplanung: markiert Tage, an denen
/// bereits ein Video geplant ist, und erlaubt die Datumswahl per Klick
/// (die eingestellte Uhrzeit bleibt dabei erhalten).
struct SchedulePlanCalendar: View {
    @Binding var selection: Date
    /// Veröffentlichungstermine aller anderen Aufträge in der Warteschlange
    let planned: [PlannedEntry]

    @State private var displayedMonth = Date()
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 6) {
            header
            weekdayRow
            dayGrid
            legend
        }
        .onAppear { displayedMonth = selection }
        .onChange(of: selection) { newValue in
            // Wenn das Datum über den DatePicker in einen anderen Monat
            // geändert wird, blättert der Kalender mit.
            if !calendar.isDate(newValue, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = newValue
            }
        }
    }

    // MARK: - Teilansichten

    private var header: some View {
        HStack {
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth)!
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Spacer()
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.callout.weight(.semibold))
            Spacer()
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth)!
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
    }

    private var weekdaySymbols: [String] {
        let syms = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(syms[first...] + syms[..<first])
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                Text("Gewählter Termin")
            }
            HStack(spacing: 5) {
                Circle().fill(Color.orange.opacity(0.25))
                    .overlay(Circle().stroke(Color.orange, lineWidth: 1))
                    .frame(width: 8, height: 8)
                Text("Bereits ein Video geplant")
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))!
    }

    private var dayGrid: some View {
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)!.count
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingBlanks = (weekday - calendar.firstWeekday + 7) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 30)
            }
            ForEach(1...daysInMonth, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
        let isSelected = calendar.isDate(date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(date)
        let entriesForDay = planned.filter { calendar.isDate($0.date, inSameDayAs: date) }
        let isOccupied = !entriesForDay.isEmpty
        let isPast = date < calendar.startOfDay(for: Date())

        return Button {
            select(date)
        } label: {
            Text("\(day)")
                .font(.callout)
                .monospacedDigit()
                .frame(width: 28, height: 28)
                .background(background(isSelected: isSelected, isOccupied: isOccupied))
                .foregroundStyle(isSelected ? Color.white : (isPast ? Color.secondary : Color.primary))
                .overlay {
                    if isToday && !isSelected {
                        Circle().stroke(Color.accentColor, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isPast)
        .help(entriesForDay.isEmpty
              ? ""
              : "Bereits geplant: " + entriesForDay.map(\.title).joined(separator: ", "))
    }

    @ViewBuilder
    private func background(isSelected: Bool, isOccupied: Bool) -> some View {
        if isSelected {
            Circle().fill(Color.accentColor)
        } else if isOccupied {
            Circle().fill(Color.orange.opacity(0.25))
                .overlay(Circle().stroke(Color.orange, lineWidth: 1.5))
        }
    }

    /// Übernimmt den angeklickten Tag, behält aber die gewählte Uhrzeit.
    private func select(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: selection)
        selection = calendar.date(
            bySettingHour: time.hour ?? 12,
            minute: time.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }
}
