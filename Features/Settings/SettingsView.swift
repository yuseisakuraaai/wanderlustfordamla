import SwiftUI
import Combine
import PhotosUI
import Photos
import UIKit
import UniformTypeIdentifiers
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

struct SettingsView: View {
    @AppStorage("atlas.username") private var username = ""
    @AppStorage("atlas.email") private var email = ""
    @AppStorage("atlas.homeCountry") private var homeCountry = ""
    @AppStorage("atlas.appearance") private var appearance = WanderlustAppearance.system.rawValue
    @AppStorage("atlas.profilePhotoData") private var profilePhotoData = Data()
    @AppStorage("atlas.homeCountryHighlight") private var homeCountryHighlight = true
    @AppStorage("atlas.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("atlas.hasSeenIntroPages") private var hasSeenIntroPages = false

    // シングルトンは View の所有物ではないので @ObservedObject を使う
    @ObservedObject private var tripStore = TripStore.shared
    /// 広告プライバシー設定の行を出すか（UMP の判定結果）。
    @State private var showsAdPrivacyOptions = false
    @StateObject private var authenticationStore = AuthenticationStore.shared
    @StateObject private var syncQueueStore = SyncQueueStore.shared

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showLanguageSettingsAlert = false
    @State private var showPhotoActionDialog = false
    @State private var showPhotoPicker = false
    @State private var showPhotoDeniedAlert = false
    @State private var selectedProfileImage: UIImage?
    @State private var showPhotoCropper = false
    @State private var isLoadingProfilePhoto = false
    @State private var localProfilePhotoData = Data()
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var message: SettingsMessage?
    @State private var showProfilePhotoSavedToast = false
    @State private var showEmailCopiedAlert = false
    @State private var profilePhotoSavedToastTask: Task<Void, Never>?
    @State private var backupDocument: WanderlustDataDocument?
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var pendingRestore: WanderlustBackupPreview?
    @State private var showAccountSignIn = false
    @State private var showTermsSafari = false
    @State private var showPrivacySafari = false
    @State private var showDeleteReauthSheet = false
    @State private var pendingMailKind: SettingsMailKind = .feedback
    @State private var showMailConfirmation = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var currentLanguage: String {
        switch currentBundleLanguageCode {
        case "ja":
            return "日本語"
        case "de":
            return "Deutsch"
        default:
            return "English"
        }
    }

    private var currentBundleLanguageCode: String {
        let rawCode = Bundle.main.preferredLocalizations.first
            ?? Bundle.main.developmentLocalization
            ?? "en"
        return rawCode
            .split(separator: "@", maxSplits: 1)
            .first?
            .split(whereSeparator: { $0 == "_" || $0 == "-" })
            .first?
            .lowercased() ?? "en"
    }

    private var displayName: String {
        let cleanName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanName.isEmpty ? WanderlustL10n.string("Username not set", table: .account) : cleanName
    }

    private var displayEmail: String {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanEmail.isEmpty ? WanderlustL10n.string("Local account", table: .account) : cleanEmail
    }

    private var shouldShowAccountSection: Bool {
        authenticationStore.authenticationState != .signedOut ||
            authenticationStore.currentUser != nil ||
            !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentAppearanceTitle: String {
        WanderlustAppearance(rawValue: appearance)?.title ?? WanderlustAppearance.system.title
    }

    var body: some View {
        List {
            profileSection
            if shouldShowAccountSection {
                accountSection
            }
            customizationSection
            permissionSection
            supportSection
            legalSection
            dataSection
            accountActionsSection
            appFooter
        }
        .listStyle(.insetGrouped)
        .navigationTitle(WanderlustL10n.string("Settings", table: .settings))
        .toolbarTitleDisplayMode(.large)
        .task {
            showsAdPrivacyOptions = AdConsentCoordinator.shared.isPrivacyOptionsRequired
        }
        .sheet(item: $message) { message in
            SettingsExplanationView(message: message) {
                showEmailCopiedAlert = true
            }
        }
        .fullScreenCover(isPresented: $showAccountSignIn) {
            OnboardingFlowView(
                startsAtAuthentication: true,
                onAuthenticationBack: {
                    showAccountSignIn = false
                },
                onCompletion: {
                    showAccountSignIn = false
                }
            )
        }
        .sheet(isPresented: $showPhotoCropper) {
            if let selectedProfileImage {
                PhotoCropView(image: selectedProfileImage) { croppedImage in
                    if let data = croppedImage.jpegData(compressionQuality: 0.84) {
                        Task {
                            _ = await saveProfilePhoto(data)
                            try? await Task.sleep(for: .milliseconds(250))
                            presentProfilePhotoSavedToast()
                        }
                    }
                    self.selectedProfileImage = nil
                    showPhotoCropper = false
                } onCancel: {
                    self.selectedProfileImage = nil
                    showPhotoCropper = false
                }
            }
        }
        .onChange(of: photoPickerItem) {
            loadSelectedPhoto()
        }
        .onDisappear {
            photoLoadTask?.cancel()
            photoLoadTask = nil
            profilePhotoSavedToastTask?.cancel()
            profilePhotoSavedToastTask = nil
        }
        .task {
            await loadLocalProfilePhoto()
        }
        .onChange(of: authenticationStore.currentUser?.id) {
            handleCurrentUserIDChange()
        }
        .onChange(of: authenticationStore.currentUser?.email) {
            handleCurrentUserEmailChange()
        }
        .onChange(of: appearance) { syncCloudSettings() }
        .onChange(of: homeCountryHighlight) { syncCloudSettings() }
        .onChange(of: homeCountry) { syncCloudSettings() }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoPickerItem,
            matching: .images
        )
        .fileExporter(
            isPresented: $showBackupExporter,
            document: backupDocument,
            contentType: .wanderlustBackup,
            defaultFilename: "wanderlust-backup.wanderlustbackup"
        ) { result in handleBackupExportCompletion(result) }
        .fileImporter(
            isPresented: $showBackupImporter,
            allowedContentTypes: [.wanderlustBackup, .atlasBackup, .json],
            allowsMultipleSelection: false
        ) { result in
            handleBackupImport(result)
        }
        .modifier(SettingsEmailCopiedAlert(isPresented: $showEmailCopiedAlert))
        .alert(
            pendingMailKind.title,
            isPresented: $showMailConfirmation
        ) {
            Button(String(localized: "OK")) {
                openMail(kind: pendingMailKind)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
                .tint(.blue)
                .fontWeight(.regular)
        } message: {
            Text(WanderlustL10n.string("Open Mail to continue?", table: .settings, fallback: "Open Mail to continue?"))
        }
        .alert(
            WanderlustL10n.string("Restore Backup Alert Title", table: .settings),
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            )
        ) {
            Button(WanderlustL10n.string("Restore Backup", table: .settings), role: .destructive) {
                applyPendingRestore()
            }
            Button(String(localized: "Cancel"), role: .cancel) {
                pendingRestore = nil
            }
            .tint(.blue)
            .fontWeight(.regular)
        } message: {
            if let pendingRestore {
                Text(pendingRestore.confirmationMessage)
            }
        }
        .alert(
            WanderlustL10n.string("Photos Access Needed", table: .errors),
            isPresented: $showPhotoDeniedAlert
        ) {
            Button(WanderlustL10n.string("Open Settings", table: .settings)) {
                openAppSettings()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
                .tint(.blue)
                .fontWeight(.regular)
        } message: {
            Text(WanderlustL10n.string("Allow photo access in iPhone Settings to choose a profile photo.", table: .account))
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
        .overlay(alignment: .bottom) {
            if showProfilePhotoSavedToast {
                SettingsSavedToast(
                    text: WanderlustL10n.string(
                        "Profile photo saved.",
                        table: .settings,
                        fallback: "Profile photo saved."
                    )
                )
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showProfilePhotoSavedToast)
        .onChange(of: authenticationStore.requiresReauthForDeletion) { _, needed in
            if needed { showDeleteReauthSheet = true }
        }
        .sheet(isPresented: $showDeleteReauthSheet, onDismiss: {
            authenticationStore.cancelReauthForDeletion()
        }) {
            DeleteAccountReauthView(
                accountType: authenticationStore.currentUser?.accountType ?? "email"
            ) {
                deleteLocalAccount()
                hasSeenIntroPages = true
                hasCompletedOnboarding = false
            }
        }
    }

    private var profileSection: some View {
        Section {
            NavigationLink {
                EditProfileSheet(
                    username: $username,
                    homeCountry: $homeCountry,
                    profilePhotoData: profilePhotoBinding,
                    onProfilePhotoSaved: { data in
                        await saveProfilePhoto(data)
                    },
                    onProfilePhotoDeleted: {
                        await removeProfilePhoto()
                    }
                )
            } label: {
                HStack(spacing: 16) {
                    profileAvatar
                        .accessibilityLabel(WanderlustL10n.string("Profile Photo", table: .account))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName)
                            .font(.headline)

                        let cleanedCountry = homeCountry.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanedCountry.isEmpty {
                            let country = GeoJSONLoader.shared.country(withISOCode: cleanedCountry)
                                ?? GeoJSONLoader.shared.country(named: cleanedCountry)
                            Text("\(country?.flagEmoji ?? "🌍") \(localizedHomeCountryName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)

                    Spacer()
                }
                .padding(.vertical, 6)
            }
        } header: {
            settingsSectionHeader(WanderlustL10n.string("Profile", table: .account))
        }
    }

    private var accountSection: some View {
        Section {
            NavigationLink {
                AccountInformationView()
            } label: {
                settingsRow(
                    icon: "person.text.rectangle.fill",
                    color: .blue,
                    label: WanderlustL10n.string("Account Information", table: .account)
                )
            }
        } header: {
            settingsSectionHeader(WanderlustL10n.string("Account", table: .account))
        }
    }

    private var syncSection: some View {
        Section {
            HStack(spacing: 12) {
                settingsIcon(systemName: syncStatusIcon, color: syncStatusColor)
                Text(WanderlustL10n.string("Sync", table: .settings, fallback: "Sync"))
                Spacer()
                Text(syncStatusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if case .failed = syncQueueStore.syncState {
                Button {
                    syncQueueStore.retryFailed()
                } label: {
                    Label(
                        WanderlustL10n.string("Retry", table: .settings, fallback: "Retry"),
                        systemImage: "arrow.clockwise"
                    )
                }
            }
        } header: {
            settingsSectionHeader(WanderlustL10n.string("Sync", table: .settings, fallback: "Sync"))
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
        let dateText = date.formatted(date: .abbreviated, time: .shortened)
        let format = WanderlustL10n.string("Last synced format", table: .settings, fallback: "Last synced %@")
        return String(format: format, dateText)
    }

    private var syncStatusIcon: String {
        switch syncQueueStore.syncState {
        case .synced:
            return "checkmark.circle.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .offline:
            return "wifi.slash"
        case .failed, .conflict:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "arrow.triangle.2.circlepath"
        }
    }

    private var syncStatusColor: Color {
        switch syncQueueStore.syncState {
        case .synced:
            return .green
        case .syncing, .idle:
            return .blue
        case .offline:
            return .gray
        case .failed, .conflict:
            return .red
        }
    }

    private var customizationSection: some View {
        Section {
            HStack(spacing: 12) {
                settingsIcon(systemName: "circle.lefthalf.filled", color: SettingsIconPalette.black)
                Text(WanderlustL10n.string("Appearance", table: .settings))
                Spacer()
                Picker("", selection: $appearance) {
                    ForEach(WanderlustAppearance.allCases) { app in
                        Text(app.title).tag(app.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(.blue)
            }
            .foregroundStyle(.primary)

            Button {
                showLanguageSettingsAlert = true
            } label: {
                languageSettingsRow
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            if !homeCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Toggle(isOn: $homeCountryHighlight) {
                    HStack(spacing: 12) {
                        settingsIcon(systemName: "house.fill", color: SettingsIconPalette.orange)
                        Text(WanderlustL10n.string("Home Country Highlight", table: .account))
                    }
                }
                .tint(.orange)
            }
        } header: {
            settingsSectionHeader(WanderlustL10n.string("Customization", table: .settings))
        }
    }

    private var permissionSection: some View {
        Section {
            Button {
                openAppSettings()
            } label: {
                settingsRow(
                    icon: "location.fill",
                    color: SettingsIconPalette.green,
                    label: WanderlustL10n.string("Location", table: .settings),
                    value: WanderlustL10n.string("Manage", table: .settings)
                )
            }
            .foregroundStyle(.primary)

            Button {
                openAppSettings()
            } label: {
                settingsRow(
                    icon: "bell.badge.fill",
                    color: SettingsIconPalette.red,
                    label: WanderlustL10n.string("Notifications", table: .settings),
                    value: WanderlustL10n.string("Manage", table: .settings)
                )
            }
            .foregroundStyle(.primary)

            // 広告のプライバシー設定（同意の再取得）。
            // UMP が「必要」と判断した地域（EEA / 英国など）でのみ表示する。
            // GDPR では一度与えた同意を後から変更できる導線が求められる。
            if showsAdPrivacyOptions {
                Button {
                    Task { await AdConsentCoordinator.shared.presentPrivacyOptionsForm() }
                } label: {
                    settingsRow(
                        icon: "hand.raised.fill",
                        color: SettingsIconPalette.blue,
                        label: String(localized: "Ad Privacy Settings"),
                        value: WanderlustL10n.string("Manage", table: .settings)
                    )
                }
                .foregroundStyle(.primary)
            }
        } header: {
            settingsSectionHeader(WanderlustL10n.string("Permissions", table: .settings))
        }
    }

    private var supportSection: some View {
        Section {
            NavigationLink {
                DeveloperSupportView()
            } label: {
                blueSettingsRow(
                    icon: "heart.fill",
                    label: WanderlustL10n.string("Support the Developer", table: .settings),
                    iconColor: SettingsIconPalette.blue,
                    labelColor: .primary
                )
            }

            Button {
                confirmMailOpening(kind: .feedback)
            } label: {
                blueSettingsRow(
                    icon: "bubble.left.and.bubble.right.fill",
                    label: WanderlustL10n.string("Send Feedback", table: .settings),
                    iconColor: SettingsIconPalette.orange,
                    labelColor: .primary
                )
            }
            .buttonStyle(.plain)

            Button {
                confirmMailOpening(kind: .contact)
            } label: {
                blueSettingsRow(
                    icon: "envelope.fill",
                    label: WanderlustL10n.string("Contact Us", table: .account),
                    iconColor: SettingsIconPalette.green,
                    labelColor: .primary
                )
            }
            .buttonStyle(.plain)

            Button {
                // Store URL is not available yet.
            } label: {
                blueSettingsRow(
                    icon: "star.fill",
                    label: WanderlustL10n.string("Rate on the App Store", table: .settings, fallback: "Rate on the App Store"),
                    iconColor: SettingsIconPalette.yellow,
                    labelColor: .primary
                )
            }
            .buttonStyle(.plain)
        } header: {
            settingsSectionHeader(WanderlustL10n.string("Support", table: .settings))
        }
    }

    private var legalSection: some View {
        Section {
            Button {
                showTermsSafari = true
            } label: {
                infoSettingsRow(
                    icon: "doc.plaintext",
                    label: WanderlustL10n.string("Terms of Service", table: .settings),
                    iconColor: SettingsIconPalette.black
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showTermsSafari) {
                WanderlustSafariSheet(url: SupportLinks.terms)
            }

            Button {
                showPrivacySafari = true
            } label: {
                infoSettingsRow(
                    icon: "hand.raised.fill",
                    label: WanderlustL10n.string("Privacy Policy", table: .settings),
                    iconColor: SettingsIconPalette.blue
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPrivacySafari) {
                WanderlustSafariSheet(url: SupportLinks.privacy)
            }

            NavigationLink {
                LicensesView()
            } label: {
                infoSettingsRow(
                    icon: "shippingbox.fill",
                    label: WanderlustL10n.string("Licenses", table: .settings),
                    iconColor: SettingsIconPalette.orange
                )
            }

            NavigationLink {
                FutureFeaturesView()
            } label: {
                infoSettingsRow(
                    icon: "sparkles",
                    label: WanderlustL10n.string("Future Features", table: .settings),
                    iconColor: SettingsIconPalette.green
                )
            }
        } header: {
            settingsSectionHeader(WanderlustL10n.string("Information", table: .settings))
        }
    }

    private var languageSettingsRow: some View {
        HStack(spacing: 12) {
            settingsIcon(systemName: "globe", color: SettingsIconPalette.blue)
            Text(WanderlustL10n.string("Language", table: .settings))
            Spacer()
            Text(currentLanguage)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .confirmationDialog(
                    WanderlustL10n.string("Language", table: .settings),
                    isPresented: $showLanguageSettingsAlert
                ) {
                    Button(WanderlustL10n.string("Open Settings", table: .settings)) {
                        openAppSettingsAfterDialogDismissal()
                    }
                    Button(String(localized: "Cancel"), role: .cancel) {}
                        .tint(.blue)
                        .fontWeight(.regular)
                } message: {
                    Text(WanderlustL10n.string("Wanderlust uses the iPhone app language setting. Change the app language in Settings.", table: .settings))
                }
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                createBackup()
            } label: {
                blueSettingsRow(
                    icon: "externaldrive.fill",
                    label: WanderlustL10n.string("Backup All Data", table: .settings)
                )
            }
            .buttonStyle(.plain)

            Button {
                showBackupImporter = true
            } label: {
                blueSettingsRow(
                    icon: "arrow.clockwise",
                    label: WanderlustL10n.string("Restore from Backup", table: .settings)
                )
            }
            .buttonStyle(.plain)
        } header: {
            settingsSectionHeader(WanderlustL10n.string("Data", table: .settings))
        }
    }

    private var appFooter: some View {
        Section {
            Text("\(versionFooterLabel): \(appVersion)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private var versionFooterLabel: String {
        if currentBundleLanguageCode == "ja" {
            return "バージョン"
        }

        return "Version"
    }

    private var accountActionsSection: some View {
        Section {
            if authenticationStore.authenticationState == .signedOut {
                Button {
                    showAccountSignIn = true
                } label: {
                    blueSettingsRow(
                        icon: "person.crop.circle",
                        label: WanderlustL10n.string("Log In to Account", table: .account)
                    )
                }
                .buttonStyle(.plain)
            }

            if authenticationStore.authenticationState == .signedIn {
                NavigationLink {
                    AccountActionConfirmationView(kind: .logout) {
                        let didSignOut = await authenticationStore.signOut()
                        if didSignOut {
                            email = ""
                            localProfilePhotoData = Data()
                            profilePhotoData = Data()
                            hasSeenIntroPages = true
                            hasCompletedOnboarding = false
                        }
                    }
                } label: {
                    destructiveSettingsRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        label: WanderlustL10n.string("Log Out", table: .account)
                    )
                }

                NavigationLink {
                    AccountActionConfirmationView(kind: .deleteAccount) {
                        let didDelete = await authenticationStore.deleteAccount()
                        if didDelete {
                            deleteLocalAccount()
                            hasSeenIntroPages = true
                            hasCompletedOnboarding = false
                        }
                    }
                } label: {
                    destructiveSettingsRow(
                        icon: "person.crop.circle.badge.xmark",
                        label: WanderlustL10n.string("Delete Account", table: .account)
                    )
                }
            }
        } header: {
            settingsSectionHeader(WanderlustL10n.string("Account Actions", table: .account))
        }
    }

    private var localizedHomeCountryName: String {
        let cleaned = homeCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return WanderlustL10n.string("Not Set", table: .settings)
        }

        if let country = GeoJSONLoader.shared.country(withISOCode: cleaned) {
            return country.displayName
        }

        if let country = GeoJSONLoader.shared.country(named: cleaned) {
            return country.displayName
        }

        return cleaned
    }

    @ViewBuilder
    private var profileAvatar: some View {
        ZStack(alignment: .bottomTrailing) {
            if let uiImage = UIImage(data: displayedProfilePhotoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .wanderlustDecorativeFont(64)
                    .foregroundStyle(.blue)
            }

            if isLoadingProfilePhoto {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 64, height: 64)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
    }

    private var displayedProfilePhotoData: Data {
        localProfilePhotoData.isEmpty ? profilePhotoData : localProfilePhotoData
    }

    private var profilePhotoBinding: Binding<Data> {
        Binding(
            get: { displayedProfilePhotoData },
            set: { newValue in
                profilePhotoData = newValue
                localProfilePhotoData = newValue
            }
        )
    }

    private var hasProfilePhoto: Bool {
        !displayedProfilePhotoData.isEmpty
    }

    private func createBackup() {
        Task {
            do {
                let backup = WanderlustBackupEnvelope(
                    schemaVersion: 1,
                    appVersion: appVersion,
                    createdAt: Date(),
                    payload: WanderlustBackupPayload(
                        trips: tripStore.trips,
                        username: username,
                        email: email,
                        homeCountry: homeCountry,
                        profilePhotoData: profilePhotoData,
                        appearance: appearance,
                        homeCountryHighlight: homeCountryHighlight,
                        hasCompletedOnboarding: hasCompletedOnboarding
                    )
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(backup)
                await MainActor.run {
                    backupDocument = WanderlustDataDocument(data: data)
                    showBackupExporter = true
                }
            } catch {
                message = SettingsMessage(
                    title: WanderlustL10n.string("Backup All Data", table: .settings),
                    systemImage: "exclamationmark.triangle.fill",
                    body: error.localizedDescription
                )
            }
        }
    }

    private func handleFileExportResult(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            message = SettingsMessage(
                title: WanderlustL10n.string("Export Failed", table: .errors),
                systemImage: "exclamationmark.triangle.fill",
                body: error.localizedDescription
            )
        }
    }

    private func handleBackupImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessed {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let backup = try decoder.decode(WanderlustBackupEnvelope.self, from: data)
                    guard backup.schemaVersion == 1 else {
                        throw WanderlustBackupError.unsupportedVersion
                    }
                    await MainActor.run {
                        pendingRestore = WanderlustBackupPreview(backup: backup)
                    }
                } catch {
                    await MainActor.run {
                        message = SettingsMessage(
                            title: WanderlustL10n.string("Restore from Backup", table: .settings),
                            systemImage: "exclamationmark.triangle.fill",
                            body: error.localizedDescription
                        )
                    }
                }
            }
        case .failure(let error):
            message = SettingsMessage(
                title: WanderlustL10n.string("Restore from Backup", table: .settings),
                systemImage: "exclamationmark.triangle.fill",
                body: error.localizedDescription
            )
        }
    }

    private func applyPendingRestore() {
        guard let pendingRestore else {
            return
        }

        let payload = pendingRestore.backup.payload
        username = payload.username
        email = payload.email
        homeCountry = payload.homeCountry
        profilePhotoData = payload.profilePhotoData
        appearance = payload.appearance
        homeCountryHighlight = payload.homeCountryHighlight
        hasCompletedOnboarding = payload.hasCompletedOnboarding
        _ = tripStore.mergeRestoredTrips(payload.trips)
        self.pendingRestore = nil
    }

    private func settingsRow(
        icon: String,
        color: Color,
        label: String,
        value: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            settingsIcon(systemName: icon, color: color)
            Text(label)
            Spacer()
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func blueSettingsRow(
        icon: String,
        label: String,
        iconColor: Color = .blue,
        labelColor: Color = .blue
    ) -> some View {
        HStack(spacing: 12) {
            settingsIcon(systemName: icon, color: iconColor)
            Text(label)
                .foregroundStyle(labelColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func infoSettingsRow(
        icon: String,
        label: String,
        iconColor: Color = .blue,
        labelColor: Color = .primary,
    ) -> some View {
        HStack(spacing: 12) {
            settingsIcon(systemName: icon, color: iconColor)
            Text(label)
                .foregroundStyle(labelColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func destructiveSettingsRow(icon: String, label: String) -> some View {
        HStack(spacing: 12) {
            settingsIcon(systemName: icon, color: .red)
            Text(label)
                .foregroundStyle(.red)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, -12)
    }

    private func settingsIcon(systemName: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)

            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
    }

    private func syncCloudSettings() {
        authenticationStore.syncSettings(
            appearance: appearance,
            homeCountryHighlight: homeCountryHighlight,
            homeCountryISO2: homeCountry
        )
    }

    @MainActor
    private func presentProfilePhotoSavedToast() {
        profilePhotoSavedToastTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            showProfilePhotoSavedToast = true
        }
        profilePhotoSavedToastTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showProfilePhotoSavedToast = false
            }
        }
    }

    private func loadSelectedPhoto() {
        photoLoadTask?.cancel()
        isLoadingProfilePhoto = true
        photoLoadTask = Task {
            guard let photoPickerItem else {
                isLoadingProfilePhoto = false
                return
            }

            do {
                guard let data = try await photoPickerItem.loadTransferable(type: Data.self) else {
                    message = SettingsMessage(
                        title: WanderlustL10n.string("Profile Photo", table: .account),
                        systemImage: "photo.fill",
                        body: WanderlustL10n.string("Wanderlust could not read the selected photo. Please choose another image.", table: .errors)
                    )
                    self.photoPickerItem = nil
                    isLoadingProfilePhoto = false
                    return
                }

                guard let uiImage = await ProfilePhotoRenderer.previewImage(from: data) else {
                    message = SettingsMessage(
                        title: WanderlustL10n.string("Profile Photo", table: .account),
                        systemImage: "photo.fill",
                        body: WanderlustL10n.string("Wanderlust could not read the selected photo. Please choose another image.", table: .errors)
                    )
                    self.photoPickerItem = nil
                    isLoadingProfilePhoto = false
                    return
                }

                guard !Task.isCancelled else { return }
                selectedProfileImage = uiImage
                showPhotoCropper = true
            } catch {
                guard !Task.isCancelled else { return }
                message = SettingsMessage(
                    title: WanderlustL10n.string("Profile Photo", table: .account),
                    systemImage: "photo.fill",
                    body: WanderlustL10n.string("Wanderlust could not read the selected photo. Check Photos access in iPhone Settings and try again.", table: .errors)
                )
            }

            self.photoPickerItem = nil
            isLoadingProfilePhoto = false
        }
    }

    @MainActor
    private func saveProfilePhoto(_ data: Data) async -> Data {
        guard !data.isEmpty else {
            await removeProfilePhoto()
            return Data()
        }

        guard let uid = authenticationStore.currentUser?.id else {
            profilePhotoData = data
            localProfilePhotoData = Data()
            return data
        }

        if let savedData = try? await ProfilePhotoLocalStore.save(data, uid: uid) {
            localProfilePhotoData = savedData
            profilePhotoData = savedData
            return savedData
        } else {
            profilePhotoData = data
            localProfilePhotoData = Data()
            return data
        }
    }

    @MainActor
    private func loadLocalProfilePhoto() async {
        guard let uid = authenticationStore.currentUser?.id else {
            localProfilePhotoData = Data()
            return
        }
        let loadedData = await ProfilePhotoLocalStore.loadData(uid: uid) ?? Data()
        guard authenticationStore.currentUser?.id == uid else { return }
        if !loadedData.isEmpty {
            localProfilePhotoData = loadedData
            if profilePhotoData.isEmpty {
                profilePhotoData = loadedData
            }
        } else {
            localProfilePhotoData = Data()
        }
    }

    @MainActor
    private func removeProfilePhoto() async {
        if let uid = authenticationStore.currentUser?.id {
            try? await ProfilePhotoLocalStore.delete(uid: uid)
        }
        localProfilePhotoData = Data()
        profilePhotoData = Data()
    }

    private func requestPhotoSelection() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            showPhotoPicker = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                Task { @MainActor in
                    switch status {
                    case .authorized, .limited:
                        showPhotoPicker = true
                    case .denied, .restricted:
                        showPhotoDeniedAlert = true
                    case .notDetermined:
                        break
                    @unknown default:
                        showPhotoDeniedAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showPhotoDeniedAlert = true
        @unknown default:
            showPhotoPicker = true
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url, options: [:])
    }

    private func handleCurrentUserIDChange() {
        Task {
            await loadLocalProfilePhoto()
        }

        if let currentUser = authenticationStore.currentUser {
            email = currentUser.email
            username = currentUser.name
            if let restoredHomeCountry = currentUser.homeCountryISO2,
               !restoredHomeCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                homeCountry = restoredHomeCountry
            }
            if let restoredPhotoData = currentUser.profilePhotoData, !restoredPhotoData.isEmpty {
                profilePhotoData = restoredPhotoData
                localProfilePhotoData = restoredPhotoData
            }
        }

        syncCloudSettings()
    }

    private func handleCurrentUserEmailChange() {
        if let currentUser = authenticationStore.currentUser {
            email = currentUser.email
        }
    }

    private func handleBackupExportCompletion(_ result: Result<URL, Error>) {
        handleFileExportResult(result)
        backupDocument = nil
    }

    private func openAppSettingsAfterDialogDismissal() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            openAppSettings()
        }
    }

    private func confirmMailOpening(kind: SettingsMailKind) {
        pendingMailKind = kind
        showMailConfirmation = true
    }

    private func openMail(kind: SettingsMailKind) {
        let recipient = SupportConstants.email
        let subject = kind.subject
        let body = kind.body(
            appVersion: appVersion,
            supportID: supportIdentifier
        )
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "mailto:\(recipient)?subject=\(encodedSubject)&body=\(encodedBody)"),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            message = SettingsMessage(
                title: kind.title,
                systemImage: "envelope.fill",
                body: """
                \(WanderlustL10n.string("Mail is not configured on this device.", table: .errors, fallback: "Mail is not configured on this device."))
                \(recipient)
                """
            )
        }
    }

    private var supportIdentifier: String {
        if let user = authenticationStore.currentUser, !user.isLocalOnly {
            return user.id
        }
        return WanderlustL10n.string("Not Available", table: .account, fallback: "Not Available")
    }

    private func deleteLocalAccount() {
        username = ""
        email = ""
        homeCountry = ""
        profilePhotoData = Data()
        homeCountryHighlight = true
        appearance = WanderlustAppearance.system.rawValue

        message = SettingsMessage(
            title: WanderlustL10n.string("Delete Account", table: .account),
            systemImage: "trash.fill",
            body: WanderlustL10n.string("Local Wanderlust profile data was deleted from this device. Trips, flights, photos, settings, and permission choices were kept.", table: .account)
        )
    }
}

private enum SettingsIconPalette {
    static let blue = Color.blue
    static let green = Color(uiColor: .systemGreen)
    static let red = Color(uiColor: .systemRed)
    static let orange = Color(uiColor: .systemOrange)
    static let yellow = Color(uiColor: .systemYellow)
    static let teal = Color(uiColor: .systemTeal)
    static let pink = Color(uiColor: .systemPink)
    static let indigo = Color(uiColor: .systemIndigo)
    static let purple = Color(red: 0.46, green: 0.40, blue: 0.78)
    static let brown = Color(uiColor: .systemBrown)
    static let gray = Color(uiColor: .systemGray2)
    static let black = Color.black
}

private struct SettingsEmailCopiedAlert: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert(
            WanderlustL10n.string("Email address copied.", table: .settings, fallback: "Email address copied."),
            isPresented: $isPresented
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        }
    }
}
