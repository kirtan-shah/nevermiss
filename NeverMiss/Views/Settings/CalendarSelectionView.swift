import SwiftUI

struct CalendarSelectionView: View {

    // MARK: - Properties

    let syncManager = CalendarSyncManager.shared
    let settings = SettingsManager.shared

    private let maxGoogleCalendars = 3

    @State private var isRefreshing = false

    private var selectedGoogleCalendarCount: Int {
        settings.selectedCalendarIds.filter { id in
            syncManager.availableCalendars.first { $0.id == id }?.source == .google
        }.count
    }

    private var isGoogleAtLimit: Bool {
        selectedGoogleCalendarCount >= maxGoogleCalendars
    }

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
                    calendarRow(calendar, limitReached: source == .google && isGoogleAtLimit)
                }

                if source == .google && isGoogleAtLimit {
                    Text("NeverMiss supports up to \(maxGoogleCalendars) Google calendars")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                HStack {
                    Image(systemName: icon)
                    Text(title)
                    Spacer()
                    selectDeselectButtons(for: calendars, source: source)
                }
            }
        }
    }

    private func selectDeselectButtons(for calendars: [CalendarInfo], source: CalendarSource) -> some View {
        HStack(spacing: 8) {
            Button("Select All") {
                if source == .google {
                    let ids = Array(calendars.map { $0.id }.prefix(maxGoogleCalendars))
                    settings.deselectCalendars(calendars.map { $0.id })
                    settings.selectCalendars(ids)
                } else {
                    settings.selectCalendars(calendars.map { $0.id })
                }
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

    private func calendarRow(_ calendar: CalendarInfo, limitReached: Bool = false) -> some View {
        let isSelected = settings.selectedCalendarIds.contains(calendar.id)
        let isDisabled = !isSelected && limitReached

        return Toggle(isOn: Binding(
            get: { isSelected },
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
        .disabled(isDisabled)
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
