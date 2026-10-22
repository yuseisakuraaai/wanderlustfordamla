import SwiftUI

struct SettingsAccountLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authMode: AuthMode = .login

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            AuthBottomCard(
                mode: $authMode,
                onClose: { dismiss() },
                onAuthenticated: { _ in dismiss() }
            )
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(WanderlustL10n.string("Log In to Account", table: .account))
        .toolbarTitleDisplayMode(.inline)
    }
}

struct AccountMigrationView: View {
    @StateObject private var authenticationStore = AuthenticationStore.shared
    @State private var didFinish = false

    var body: some View {
        List {
            Section {
                Text(WanderlustL10n.string("Your trips stay on this iPhone. Migration prepares your current local data for your signed-in Wanderlust account without deleting local travel records.", table: .account))
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task {
                        didFinish = await authenticationStore.migrateLocalDataToCurrentAccount()
                    }
                } label: {
                    HStack {
                        if authenticationStore.isProcessing {
                            ProgressView()
                        }
                        Text(WanderlustL10n.string("Account Migration", table: .account))
                    }
                }
                .disabled(authenticationStore.isProcessing)
            }

            if didFinish {
                Section {
                    Label(WanderlustL10n.string("Migration completed.", table: .account), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle(WanderlustL10n.string("Account Migration", table: .account))
        .toolbarTitleDisplayMode(.inline)
    }
}

struct AccountInformationView: View {
    @StateObject private var authenticationStore = AuthenticationStore.shared
    @StateObject private var syncQueueStore = SyncQueueStore.shared
    @AppStorage("atlas.pendingEmailChangeAddress") private var pendingEmailChangeAddress = ""
    @AppStorage("atlas.didShowEmailChangeCompletion") private var didShowEmailChangeCompletion = false
    @State private var emailChangeCompleted = false
    @State private var verificationEmailSent = false
    @State private var verificationEmailSentOnce = false
    @State private var verificationCooldownRemaining = 0
    @State private var verificationCooldownTask: Task<Void, Never>?
    @State private var isSendingVerificationEmail = false

    private var user: WanderlustUser? { authenticationStore.currentUser }
    private var isEmailLogin: Bool { user?.accountType == "email" }
    private var isGoogleLogin: Bool { user?.accountType == "google" }
    private var isEmailVerified: Bool { user?.isEmailVerified ?? false }

    var body: some View {
        List {
            Section {
                accountInfoRow(
                    title: WanderlustL10n.string("Current Email Address", table: .account),
                    value: user?.email.isEmpty == false ? user?.email ?? "" : WanderlustL10n.string("Not Available", table: .account)
                )

                accountInfoRow(
                    title: WanderlustL10n.string("Login Method", table: .account),
                    value: loginMethodText
                )

                if isEmailLogin && !isEmailVerified {
                    Button {
                        sendVerificationEmail()
                    } label: {
                        HStack(spacing: 8) {
                            Text(verificationButtonTitle)
                            Spacer(minLength: 12)
                            if isSendingVerificationEmail {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isSendingVerificationEmail || verificationCooldownRemaining > 0)
                }

                if isGoogleLogin {
                    accountInfoRow(
                        title: WanderlustL10n.string("Google Account", table: .account),
                        value: user?.email ?? ""
                    )
                }

                if let creationDate = user?.creationDate {
                    accountInfoRow(
                        title: WanderlustL10n.string("Account Created", table: .account),
                        value: WanderlustDateFormatter.date(creationDate)
                    )
                }

                accountInfoRow(
                    title: WanderlustL10n.string("Data Last Synced", table: .account, fallback: "Data Last Synced"),
                    value: syncStatusText
                )
            }

            if isEmailLogin {
                Section {
                    NavigationLink {
                        EmailChangeView()
                    } label: {
                        Label(WanderlustL10n.string("Change Email Address", table: .account), systemImage: "envelope")
                    }

                    NavigationLink {
                        PasswordChangeView()
                    } label: {
                        Label(WanderlustL10n.string("Change Password", table: .account), systemImage: "key.fill")
                    }
                }
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle(WanderlustL10n.string("Account Information", table: .account))
        .toolbarTitleDisplayMode(.inline)
        .task {
            await refreshPendingEmailChange()
        }
        .onDisappear {
            verificationCooldownTask?.cancel()
            verificationCooldownTask = nil
        }
        .alert(
            WanderlustL10n.string("Email Address Changed", table: .account),
            isPresented: $emailChangeCompleted
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(WanderlustL10n.string("Your email address has been updated.", table: .account))
        }
        .alert(
            WanderlustL10n.string("Verification Email Sent", table: .account, fallback: "Verification Email Sent"),
            isPresented: $verificationEmailSent
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(WanderlustL10n.string("Open the link in the email to verify your address.", table: .account, fallback: "Open the link in the email to verify your address."))
        }
        .alert(
            WanderlustL10n.string("Account", table: .account),
            isPresented: Binding(
                get: { authenticationStore.errorMessage != nil },
                set: { if !$0 { authenticationStore.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                authenticationStore.errorMessage = nil
            }
        } message: {
            Text(authenticationStore.errorMessage ?? "")
        }
    }

    private var loginMethodText: String {
        switch user?.accountType {
        case "google":
            return "Google"
        case "apple":
            return "Apple"
        case "email":
            let base = WanderlustL10n.string("Email", table: .account)
            if isEmailVerified {
                return "\(base)（\(WanderlustL10n.string("Verified", table: .account))）"
            } else {
                return "\(base)（\(WanderlustL10n.string("Unverified", table: .account))）"
            }
        case "local":
            return WanderlustL10n.string("Local account", table: .account)
        default:
            return WanderlustL10n.string("Unknown", table: .errors)
        }
    }

    private var syncStatusText: String {
        switch syncQueueStore.syncState {
        case .idle:
            return WanderlustL10n.string("Sync pending", table: .settings, fallback: "Sync pending")
        case .syncing:
            return WanderlustL10n.string("Syncing", table: .settings, fallback: "Syncing")
        case .synced(let date):
            return lastSyncedText(date)
        case .offline:
            return WanderlustL10n.string("Offline", table: .settings, fallback: "Offline")
        case .failed:
            return WanderlustL10n.string("Sync failed", table: .settings, fallback: "Sync failed")
        case .conflict:
            return WanderlustL10n.string("Conflict", table: .settings, fallback: "Conflict")
        }
    }

    private func lastSyncedText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }

    private func accountInfoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? WanderlustL10n.string("Not Available", table: .account) : value)
                .font(.body)
                .foregroundStyle(Color.primary)
        }
        .padding(.vertical, 4)
    }

    private var verificationButtonTitle: String {
        let base = verificationEmailSentOnce
            ? WanderlustL10n.string("Resend Verification Email", table: .account, fallback: "Resend Verification Email")
            : WanderlustL10n.string("Send Verification Email", table: .account, fallback: "Send Verification Email")
        if verificationCooldownRemaining > 0 {
            return "\(base) (\(verificationCooldownRemaining))"
        }
        return base
    }

    private func sendVerificationEmail() {
        guard !isSendingVerificationEmail,
              verificationCooldownRemaining == 0 else { return }

        Task {
            isSendingVerificationEmail = true
            defer { isSendingVerificationEmail = false }

            if await authenticationStore.sendEmailVerification() {
                verificationEmailSentOnce = true
                verificationEmailSent = true
                startVerificationCooldown()
            }
        }
    }

    private func startVerificationCooldown() {
        verificationCooldownTask?.cancel()
        verificationCooldownRemaining = 60
        verificationCooldownTask = Task {
            while !Task.isCancelled, verificationCooldownRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                verificationCooldownRemaining -= 1
            }
            verificationCooldownTask = nil
        }
    }

    private func refreshPendingEmailChange() async {
        guard !pendingEmailChangeAddress.isEmpty else {
            _ = await authenticationStore.reloadCurrentUser()
            return
        }
        guard let updatedUser = await authenticationStore.reloadCurrentUser() else { return }
        if updatedUser.email.localizedCaseInsensitiveCompare(pendingEmailChangeAddress) == .orderedSame {
            pendingEmailChangeAddress = ""
            if !didShowEmailChangeCompletion {
                didShowEmailChangeCompletion = true
                emailChangeCompleted = true
            }
        }
    }
}

struct PasswordChangeView: View {
    @StateObject private var authenticationStore = AuthenticationStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case current, new, confirm
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty &&
        WanderlustPasswordPolicy.isValid(newPassword) &&
        newPassword == confirmPassword &&
        !authenticationStore.isProcessing
    }

    var body: some View {
        Form {
            Section {
                SecureField(WanderlustL10n.string("Current Password", table: .account), text: $currentPassword)
                    .keyboardType(.asciiCapable)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .current)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .new }

                SecureField(WanderlustL10n.string("New Password", table: .account), text: $newPassword)
                    .keyboardType(.asciiCapable)
                    .textContentType(.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .new)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .confirm }

                SecureField(WanderlustL10n.string("Confirm New Password", table: .account), text: $confirmPassword)
                    .keyboardType(.asciiCapable)
                    .textContentType(nil)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .confirm)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            } footer: {
                Text(WanderlustL10n.string("Password change requirement footer", table: .account, fallback: "Use at least 8 characters with uppercase, lowercase, and a number. Wanderlust never displays your current password."))
            }

            Section {
                Button {
                    Task {
                        let changed = await authenticationStore.changePassword(
                            currentPassword: currentPassword,
                            newPassword: newPassword
                        )
                        if changed {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if authenticationStore.isProcessing {
                            ProgressView()
                        }
                        Text(WanderlustL10n.string("Change Password", table: .account))
                    }
                }
                .disabled(!canSubmit)
            }
        }
        .navigationTitle(WanderlustL10n.string("Change Password", table: .account))
        .toolbarTitleDisplayMode(.inline)
    }
}

struct EmailChangeView: View {
    @StateObject private var authenticationStore = AuthenticationStore.shared
    @AppStorage("atlas.pendingEmailChangeAddress") private var pendingEmailChangeAddress = ""
    @AppStorage("atlas.didShowEmailChangeCompletion") private var didShowEmailChangeCompletion = false
    @State private var newEmail = ""
    @State private var currentPassword = ""
    @State private var didSendVerification = false
    @State private var didCompleteEmailChange = false
    @State private var isSendingEmail = false
    @State private var detectionTask: Task<Void, Never>?
    @State private var resendCooldownRemaining = 0
    @State private var resendCooldownTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    private var cleanEmail: String {
        newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        cleanEmail.contains("@") &&
            !currentPassword.isEmpty &&
            !isSendingEmail &&
            resendCooldownRemaining == 0
    }

    private var confirmationButtonTitle: String {
        if didSendVerification {
            let title = WanderlustL10n.string("Resend Confirmation Email", table: .account, fallback: "Resend Confirmation Email")
            if resendCooldownRemaining > 0 {
                return "\(title) (\(resendCooldownRemaining))"
            }
            return title
        }

        return WanderlustL10n.string("Send Confirmation Email", table: .account)
    }

    var body: some View {
        Form {
            Section {
                TextField(WanderlustL10n.string("New Email Address", table: .account), text: $newEmail)
                    .textContentType(nil)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                SecureField(WanderlustL10n.string("Current Password", table: .account), text: $currentPassword)
                    .keyboardType(.asciiCapable)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            } footer: {
                Text(WanderlustL10n.string("Wanderlust will send a confirmation email before changing your address.", table: .account))
            }

            Section {
                Button {
                    Task {
                        isSendingEmail = true
                        let sent = await authenticationStore.changeEmail(
                            newEmail: cleanEmail,
                            currentPassword: currentPassword
                        )
                        isSendingEmail = false
                        if sent {
                            pendingEmailChangeAddress = cleanEmail
                            didShowEmailChangeCompletion = false
                            didSendVerification = true
                            startResendCooldown()
                            startEmailChangeDetection()
                        }
                    }
                } label: {
                    HStack {
                        if isSendingEmail {
                            ProgressView()
                        }
                        Text(confirmationButtonTitle)
                    }
                }
                .disabled(!canSubmit || isSendingEmail)
            }

            if didSendVerification {
                Section {
                    Text(WanderlustL10n.string("Confirmation email sent. Open the link in the email to complete the change.", table: .account))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(WanderlustL10n.string("Change Email Address", table: .account))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "Done")) {
                    focusedField = nil
                }
            }
        }
        .onDisappear {
            detectionTask?.cancel()
            detectionTask = nil
            resendCooldownTask?.cancel()
            resendCooldownTask = nil
        }
        .alert(
            WanderlustL10n.string("Email Address Changed", table: .account),
            isPresented: $didCompleteEmailChange
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(WanderlustL10n.string("Your email address has been updated.", table: .account))
        }
        .alert(
            WanderlustL10n.string("Account", table: .account),
            isPresented: Binding(
                get: { authenticationStore.errorMessage != nil },
                set: { if !$0 { authenticationStore.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                authenticationStore.errorMessage = nil
            }
        } message: {
            Text(authenticationStore.errorMessage ?? "")
        }
    }

    private func startEmailChangeDetection() {
        detectionTask?.cancel()
        let targetEmail = cleanEmail
        detectionTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                guard let updatedUser = await authenticationStore.reloadCurrentUser() else { continue }
                if updatedUser.email.localizedCaseInsensitiveCompare(targetEmail) == .orderedSame {
                    pendingEmailChangeAddress = ""
                    didShowEmailChangeCompletion = true
                    didCompleteEmailChange = true
                    detectionTask?.cancel()
                    detectionTask = nil
                    return
                }
            }
        }
    }

    private func startResendCooldown() {
        resendCooldownTask?.cancel()
        resendCooldownRemaining = 60
        resendCooldownTask = Task {
            while !Task.isCancelled, resendCooldownRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                resendCooldownRemaining -= 1
            }
            resendCooldownTask = nil
        }
    }
}

// MARK: - DeleteAccountReauthView

struct DeleteAccountReauthView: View {
    let accountType: String
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var authenticationStore = AuthenticationStore.shared

    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field { case password }

    private var isEmailProvider: Bool { accountType == "email" }
    private var isGoogleProvider: Bool { accountType == "google" }
    private var isAppleProvider: Bool { accountType == "apple" }

    private var currentEmail: String {
        authenticationStore.currentUser?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var canSubmitPassword: Bool {
        currentEmail.contains("@") && !password.isEmpty && !authenticationStore.isProcessing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(WanderlustL10n.string(
                        "For security, please verify your identity before deleting your account.",
                        table: .account,
                        fallback: "For security, please verify your identity before deleting your account."
                    ))
                    .foregroundStyle(.secondary)
                } header: {
                    Text(WanderlustL10n.string("Identity Verification", table: .account, fallback: "Identity Verification"))
                }

                if isEmailProvider {
                    Section {
                        SecureField(WanderlustL10n.string("Password", table: .account), text: $password)
                            .keyboardType(.asciiCapable)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .password)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }

                    Section {
                        Button(role: .destructive) {
                            Task {
                                let success = await authenticationStore.reauthenticateAndDelete(
                                    credential: .email(currentEmail, password)
                                )
                                if success {
                                    onSuccess()
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                if authenticationStore.isProcessing { ProgressView() }
                                Text(WanderlustL10n.string("Delete Account", table: .account))
                            }
                        }
                        .disabled(!canSubmitPassword)
                    }
                } else if isGoogleProvider {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                let success = await authenticationStore.reauthenticateAndDelete(credential: .google)
                                if success {
                                    onSuccess()
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                if authenticationStore.isProcessing { ProgressView() }
                                Text(WanderlustL10n.string(
                                    "Verify with Google and Delete Account",
                                    table: .account,
                                    fallback: "Verify with Google and Delete Account"
                                ))
                            }
                        }
                        .disabled(authenticationStore.isProcessing)
                    }
                } else if isAppleProvider {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                let success = await authenticationStore.reauthenticateAndDelete(credential: .apple)
                                if success {
                                    onSuccess()
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                if authenticationStore.isProcessing { ProgressView() }
                                Text(WanderlustL10n.string(
                                    "Verify with Apple and Delete Account",
                                    table: .account,
                                    fallback: "Verify with Apple and Delete Account"
                                ))
                            }
                        }
                        .disabled(authenticationStore.isProcessing)
                    }
                }

                if let errorMessage = authenticationStore.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(WanderlustL10n.string("Delete Account", table: .account))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        authenticationStore.errorMessage = nil
                        dismiss()
                    }
                    .tint(.blue)
                    .fontWeight(.regular)
                }
            }
        }
    }
}
