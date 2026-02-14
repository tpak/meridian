// Copyright © 2015 Abhishek Banthia

import SwiftUI
import CoreLoggerKit

struct PermissionsView: View {
    @StateObject private var viewModel = PermissionsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(NSLocalizedString("Permissions", comment: "Permissions Tab Title"))
                .font(.custom("Avenir-Medium", size: 27))

            permissionCard(
                header: NSLocalizedString("Calendar Access", comment: "Calendar Permission Title"),
                detail: NSLocalizedString("Calendar Detail", comment: "Calendar Detail Text"),
                status: viewModel.calendarStatus,
                isLoading: viewModel.calendarLoading,
                accessibilityID: "CalendarGrantAccessButton"
            ) {
                viewModel.requestCalendarAccess()
            }

            permissionCard(
                header: NSLocalizedString("Reminders Access", comment: "Reminders Permission Title"),
                detail: NSLocalizedString("Reminders Detail", comment: "Reminders Detail Text"),
                status: viewModel.remindersStatus,
                isLoading: viewModel.remindersLoading,
                accessibilityID: "RemindersGrantAccessButton"
            ) {
                viewModel.requestRemindersAccess()
            }

            Spacer()

            Text(NSLocalizedString("Privacy Text",
                                   comment: "Text explaining options can be changed in the future through System Preferences"))
                .font(.custom("Avenir-Light", size: 13))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { viewModel.refresh() }
    }

    @ViewBuilder
    private func permissionCard(
        header: String,
        detail: String,
        status: PermissionsViewModel.PermissionStatus,
        isLoading: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(header)
                    .font(.custom("Avenir-Roman", size: 13))

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(status.buttonTitle) {
                    action()
                }
                .disabled(status != .notDetermined)
                .accessibilityIdentifier(accessibilityID)
            }

            Text(detail)
                .font(.custom("Avenir-Light", size: 12))
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 100)
        .background(Color(nsColor: Themer.shared().textBackgroundColor()))
        .cornerRadius(12)
    }
}

@MainActor
final class PermissionsViewModel: ObservableObject {
    enum PermissionStatus {
        case granted, denied, notDetermined, unexpected

        var buttonTitle: String {
            switch self {
            case .granted:
                return NSLocalizedString("Granted Button Text", comment: "Granted Button Text")
            case .denied:
                return NSLocalizedString("Denied Button Text", comment: "Denied Button Text")
            case .notDetermined:
                return NSLocalizedString("Grant Button Text", comment: "Grant Button Text")
            case .unexpected:
                return "Unexpected".localized()
            }
        }
    }

    @Published var calendarStatus: PermissionStatus = .notDetermined
    @Published var remindersStatus: PermissionStatus = .notDetermined
    @Published var calendarLoading = false
    @Published var remindersLoading = false

    func refresh() {
        calendarStatus = currentCalendarStatus()
        remindersStatus = currentRemindersStatus()
    }

    func requestCalendarAccess() {
        let eventCenter = EventCenter.sharedCenter()
        guard eventCenter.calendarAccessNotDetermined() else {
            refresh()
            return
        }

        calendarLoading = true
        eventCenter.requestAccess(to: .event) { granted in
            Task { @MainActor [weak self] in
                self?.calendarLoading = false
                if granted {
                    self?.calendarStatus = .granted
                    NotificationCenter.default.post(name: .calendarAccessGranted, object: nil)
                } else {
                    self?.calendarStatus = .denied
                    Logger.log(object: ["Calendar Access Not Granted": "YES"],
                               for: "Calendar Access Not Granted")
                }
            }
        }
    }

    func requestRemindersAccess() {
        let eventCenter = EventCenter.sharedCenter()
        guard eventCenter.reminderAccessNotDetermined() else {
            refresh()
            return
        }

        remindersLoading = true
        eventCenter.requestAccess(to: .reminder) { granted in
            Task { @MainActor [weak self] in
                self?.remindersLoading = false
                if granted {
                    self?.remindersStatus = .granted
                } else {
                    self?.remindersStatus = .denied
                    Logger.log(object: ["Reminder Access Not Granted": "YES"],
                               for: "Reminder Access Not Granted")
                }
            }
        }
    }

    private func currentCalendarStatus() -> PermissionStatus {
        let eventCenter = EventCenter.sharedCenter()
        if eventCenter.calendarAccessGranted() { return .granted }
        if eventCenter.calendarAccessDenied() { return .denied }
        if eventCenter.calendarAccessNotDetermined() { return .notDetermined }
        return .unexpected
    }

    private func currentRemindersStatus() -> PermissionStatus {
        let eventCenter = EventCenter.sharedCenter()
        if eventCenter.reminderAccessGranted() { return .granted }
        if eventCenter.reminderAccessDenied() { return .denied }
        if eventCenter.reminderAccessNotDetermined() { return .notDetermined }
        return .unexpected
    }
}
