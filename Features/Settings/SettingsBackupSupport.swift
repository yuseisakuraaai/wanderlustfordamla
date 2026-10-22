import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsMessage: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let body: String
}

struct AccountActionConfirmationView: View {
    enum Kind {
        case logout
        case deleteAccount

        var title: String {
            switch self {
            case .logout: WanderlustL10n.string("Log Out", table: .account)
            case .deleteAccount: WanderlustL10n.string("Delete Account", table: .account)
            }
        }

        var icon: String {
            switch self {
            case .logout: "rectangle.portrait.and.arrow.right"
            case .deleteAccount: "person.crop.circle.badge.xmark"
            }
        }

        var actionTitle: String {
            switch self {
            case .logout: WanderlustL10n.string("Log Out", table: .account)
            case .deleteAccount: WanderlustL10n.string("Delete Account", table: .account)
            }
        }

        var paragraphs: [String] {
            switch self {
            case .logout:
                [
                    WanderlustL10n.string("Logging out disconnects this device from your Wanderlust account and pauses syncing until you sign in again.", table: .account),
                    WanderlustL10n.string("Your trips, cities, flights, passport stamps, statistics, backups, and app preferences remain on this device.", table: .account),
                    WanderlustL10n.string("When you sign in again, Wanderlust will reconnect your account and keep using the travel data on this device.", table: .account)
                ]
            case .deleteAccount:
                [
                    WanderlustL10n.string("Deleting your account removes the Wanderlust account profile used for sign-in and syncing.", table: .account),
                    WanderlustL10n.string("Travel records stored on this device and exported backup files are not automatically deleted.", table: .account),
                    WanderlustL10n.string("This action cannot be undone. Create a backup first if you want to keep the current data.", table: .account, fallback: "This action cannot be undone. Create a backup first if you want to keep the current data.")
                ]
            }
        }

        var confirmationTitle: String {
            switch self {
            case .logout:
                WanderlustL10n.string("Log Out?", table: .account, fallback: "Log Out?")
            case .deleteAccount:
                WanderlustL10n.string("Delete Account?", table: .account, fallback: "Delete Account?")
            }
        }

        var confirmationMessage: String {
            switch self {
            case .logout:
                WanderlustL10n.string("You can sign in again at any time. Your data on this device will remain.", table: .account, fallback: "You can sign in again at any time. Your data on this device will remain.")
            case .deleteAccount:
                WanderlustL10n.string("This permanently deletes your Wanderlust account profile. Your data on this device will remain.", table: .account, fallback: "This permanently deletes your Wanderlust account profile. Your data on this device will remain.")
            }
        }
    }

    let kind: Kind
    let performAction: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var showsActionConfirmation = false

    var body: some View {
        List {
            Section {
                confirmationCard
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            actionButton
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 76)
        }
        .navigationTitle(kind.title)
        .toolbarTitleDisplayMode(.inline)
        .alert(kind.confirmationTitle, isPresented: $showsActionConfirmation) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(kind.actionTitle, role: .destructive) {
                performConfirmedAction()
            }
        } message: {
            Text(kind.confirmationMessage)
        }
    }

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: kind.icon)
                .wanderlustFont(40, relativeTo: .largeTitle, weight: .semibold)
                .foregroundStyle(.red)
                .symbolRenderingMode(.monochrome)
                .accessibilityHidden(true)

            Text(kind.title)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(kind.paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    private var actionButton: some View {
        Button {
            guard !isProcessing else { return }
            showsActionConfirmation = true
        } label: {
            HStack {
                if isProcessing {
                    ProgressView()
                        .tint(.white)
                }
                Text(kind.actionTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.red)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: WanderlustRadius.xLarge, style: .continuous))
        }
        .disabled(isProcessing)
    }

    private func performConfirmedAction() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            await performAction()
            await MainActor.run {
                isProcessing = false
                dismiss()
            }
        }
    }
}

struct WanderlustDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .wanderlustBackup, .atlasBackup] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct WanderlustBackupEnvelope: Codable {
    let schemaVersion: Int
    let appVersion: String
    let createdAt: Date
    let payload: WanderlustBackupPayload
}

struct WanderlustBackupPayload: Codable {
    let trips: [Trip]
    let username: String
    let email: String
    let homeCountry: String
    let profilePhotoData: Data
    let appearance: String
    let homeCountryHighlight: Bool
    let hasCompletedOnboarding: Bool
}

struct WanderlustBackupPreview: Identifiable {
    let id = UUID()
    let backup: WanderlustBackupEnvelope

    private var cityCount: Int {
        backup.payload.trips.reduce(0) { $0 + $1.cities.count }
    }

    private var flightCount: Int {
        backup.payload.trips.reduce(0) { $0 + $1.flights.count }
    }

    var confirmationMessage: String {
        let created = backup.createdAt.formatted(date: .abbreviated, time: .shortened)
        return """
        \(WanderlustL10n.string("Backup Created", table: .settings)): \(created)
        \(WanderlustL10n.string("Trips", table: .trips)): \(backup.payload.trips.count)
        \(WanderlustL10n.string("Cities", table: .trips)): \(cityCount)
        \(WanderlustL10n.string("Flights", table: .settings)): \(flightCount)

        \(WanderlustL10n.string("Backup data will be merged with the data on this device.", table: .errors, fallback: "Backup data will be merged with the data on this device."))
        """
    }
}

enum WanderlustBackupError: LocalizedError {
    case unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return WanderlustL10n.string("This backup was created with an unsupported schema version.", table: .errors)
        }
    }
}

extension UTType {
    static let wanderlustBackup = UTType(filenameExtension: "wanderlustbackup") ?? .json
    static let atlasBackup = UTType(filenameExtension: "atlasbackup") ?? .json
}

enum SettingsMailKind {
    case feedback
    case contact
    case feedbackAndContact

    private var isJapanese: Bool {
        Locale.current.language.languageCode?.identifier == "ja"
    }

    var title: String {
        switch self {
        case .feedbackAndContact:
            return WanderlustL10n.string("Feedback & Contact", table: .settings, fallback: "Feedback & Contact")
        case .feedback:
            return WanderlustL10n.string("Send Feedback", table: .settings)
        case .contact:
            return WanderlustL10n.string("Contact Us", table: .account)
        }
    }

    var subject: String {
        switch (self, isJapanese) {
        case (.feedbackAndContact, true):
            return "フィードバックと問い合わせ"
        case (.feedbackAndContact, false):
            return "Feedback & Contact"
        case (.feedback, true):
            return "フィードバック"
        case (.feedback, false):
            return "Feedback"
        case (.contact, true):
            return "お問い合わせ"
        case (.contact, false):
            return "Contact"
        }
    }

    func body(appVersion: String, supportID: String) -> String {
        let device = UIDevice.current
        if isJapanese {
            let opening = switch self {
            case .feedbackAndContact:
                "フィードバックまたはお問い合わせ内容をご記入ください。"
            case .feedback:
                "Wanderlustへのフィードバックをご記入ください。"
            case .contact:
                "お問い合わせ内容をご記入ください。"
            }
            return """
            \(opening)

            ---
            アプリバージョン: \(appVersion)
            iOS: \(device.systemVersion)
            端末: \(device.model)
            サポートID: \(supportID)
            """
        }

        let opening = switch self {
        case .feedbackAndContact:
            "Please enter your feedback or inquiry."
        case .feedback:
            "Please enter your feedback about Wanderlust."
        case .contact:
            "Please enter your inquiry."
        }
        return """
        \(opening)

        ---
        App Version: \(appVersion)
        iOS: \(device.systemVersion)
        Device: \(device.model)
        Support ID: \(supportID)
        """
    }
}

struct SettingsExplanationView: View {
    let message: SettingsMessage
    var onEmailCopied: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(Color(uiColor: .secondarySystemFill))
                            .frame(width: 78, height: 78)

                        Image(systemName: message.systemImage)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)

                    Text(message.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 26)

                    if let emailMessage = parsedEmailMessage {
                        Text(emailMessage.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                            .padding(.top, 18)

                        Button {
                            UIPasteboard.general.string = emailMessage.email
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                onEmailCopied?()
                            }
                        } label: {
                            Label(
                                WanderlustL10n.string("Copy Email Address", table: .settings, fallback: "Copy Email Address"),
                                systemImage: "doc.on.doc"
                            )
                            .font(.body)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 12))
                        .controlSize(.large)
                        .padding(.top, 28)
                        .frame(maxWidth: 240)
                    } else {
                        Text(message.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 18)
                    }
                }
                .frame(maxWidth: 340)
                .padding(.horizontal, 32)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(message.title)
            .toolbarTitleDisplayMode(.inline)
        }
    }

    private var parsedEmailMessage: (message: String, email: String)? {
        let lines = message.body
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count == 2, lines[1].contains("@") {
            return (lines[0], lines[1])
        }

        guard let atIndex = message.body.firstIndex(of: "@") else {
            return nil
        }

        let prefixRange = message.body[..<atIndex]
        let separatorIndex = prefixRange.lastIndex(where: { $0 == ":" || $0 == "：" })
        guard let separatorIndex else {
            return nil
        }

        let messageText = String(message.body[...separatorIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let emailText = String(message.body[message.body.index(after: separatorIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty, !emailText.isEmpty else {
            return nil
        }

        return (messageText, emailText)
    }
}
