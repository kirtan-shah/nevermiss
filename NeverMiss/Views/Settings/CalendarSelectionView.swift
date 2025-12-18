import SwiftUI

struct CalendarSelectionView: View {

    // MARK: - Properties

    let syncManager = CalendarSyncManager.shared
    let settings = SettingsManager.shared

    @State private var isRefreshing = false

    // MARK: - Body

    var body: some View {
        Form {
            if syncManager.availableCalendars.isEmpty {
                emptyStateView
            } else {
                calendarListView
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshCalendars()
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("No Calendars Available")
                    .font(.headline)

                Text("Connect a Google account or grant access to macOS Calendar in the Accounts tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: refreshCalendars) {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Refresh")
                    }
                }
                .disabled(isRefreshing)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }

    private var calendarListView: some View {
        Group {
            calendarSection(source: .google, icon: "globe", title: "Google Calendar")
            calendarSection(source: .eventKit, icon: "calendar", title: "macOS Calendar")

            Button(action: refreshCalendars) {
                HStack {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Text("Refresh Calendars")
                }
            }
            .disabled(isRefreshing)
        }
    }

    @ViewBuilder
    private func calendarSection(source: CalendarSource, icon: String, title: String) -> some View {
        let calendars = syncManager.availableCalendars.filter { $0.source == source }
        if !calendars.isEmpty {
            Section {
                ForEach(calendars) { calendar in
                    calendarRow(calendar)
                }
            } header: {
                HStack {
                    Image(systemName: icon)
                    Text(title)
                    Spacer()
                    selectDeselectButtons(for: calendars)
                }
            }
        }
    }

    private func selectDeselectButtons(for calendars: [CalendarInfo]) -> some View {
        HStack(spacing: 8) {
            Button("Select All") {
                settings.selectCalendars(calendars.map { $0.id })
            }
            .font(.caption)

            Button("Deselect All") {
                settings.deselectCalendars(calendars.map { $0.id })
            }
            .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private func calendarRow(_ calendar: CalendarInfo) -> some View {
        Toggle(isOn: Binding(
            get: { settings.selectedCalendarIds.contains(calendar.id) },
            set: { _ in settings.toggleCalendarSelection(calendar.id) }
        )) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: calendar.color) ?? .blue)
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.name)
                        .font(.body)

                    Text(calendar.accountName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Private Helper Methods

    private func refreshCalendars() {
        isRefreshing = true
        Task {
            await syncManager.refreshCalendarList()
            isRefreshing = false
        }
    }
}

// MARK: - Preview

#Preview {
    CalendarSelectionView()
}
