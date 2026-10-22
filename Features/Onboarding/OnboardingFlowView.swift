import SwiftUI
import Combine
import CoreLocation
import UserNotifications
import UIKit
import PhotosUI
import Photos
#if canImport(GoogleSignInSwift)
import GoogleSignInSwift
#endif

// MARK: - Step

private enum OnboardingStep {
    case pages, auth, profileCompletion
}

@MainActor
private func dismissAuthenticationKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

// MARK: - Onboarding Flow View

struct OnboardingFlowView: View {
    @AppStorage("atlas.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("atlas.hasSeenIntroPages") private var hasSeenIntroPages = false
    @AppStorage("atlas.username")    private var username    = ""
    @AppStorage("atlas.email") private var email = ""
    @AppStorage("atlas.homeCountry") private var homeCountry = ""
    @AppStorage("atlas.profilePhotoData") private var profilePhotoData = Data()

    @State private var step: OnboardingStep

    private let startsAtAuthentication: Bool
    private let authenticationBackAction: (() -> Void)?
    private let completionAction: (() -> Void)?

    init(
        startsAtAuthentication: Bool = false,
        onAuthenticationBack: (() -> Void)? = nil,
        onCompletion: (() -> Void)? = nil
    ) {
        self.startsAtAuthentication = startsAtAuthentication
        self.authenticationBackAction = onAuthenticationBack
        self.completionAction = onCompletion
        self._step = State(initialValue: startsAtAuthentication ? .auth : .pages)
    }

    var body: some View {
        Group {
            switch step {
            case .pages:
                OnboardingPagesView {
                    hasSeenIntroPages = true
                    withAnimation(.easeInOut(duration: 0.4)) { step = .auth }
                }
            case .auth:
                AuthScreen(
                    onAuthenticated: handleAuthenticatedUser,
                    onBack: authenticationBackAction
                )
            case .profileCompletion:
                ProfileSetupScreen(
                    username: $username,
                    homeCountry: $homeCountry,
                    profilePhotoData: $profilePhotoData
                ) {
                    Task {
                        let updatedUser = await AuthenticationStore.shared.updateProfile(
                            name: username,
                            homeCountryISO2: homeCountry,
                            profilePhotoData: profilePhotoData.isEmpty ? nil : profilePhotoData
                        )
                        if updatedUser != nil {
                            dismissAuthenticationKeyboard()
                            completeAuthentication()
                        }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: step)
        .onAppear {
            if startsAtAuthentication {
                step = .auth
            } else if hasSeenIntroPages {
                step = .auth
            }
        }
    }

    private func completeAuthentication() {
        hasCompletedOnboarding = true
        completionAction?()
    }

    private func handleAuthenticatedUser(_ user: WanderlustUser) {
        dismissAuthenticationKeyboard()
        username = user.name
        email = user.email
        homeCountry = user.homeCountryISO2 ?? ""
        if let restoredPhotoData = user.profilePhotoData, !restoredPhotoData.isEmpty {
            profilePhotoData = restoredPhotoData
        }
        if user.profileCompleted || hasCompletedProfileFields(user) {
            completeAuthentication()
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                step = .profileCompletion
            }
        }
    }

    private func hasCompletedProfileFields(_ user: WanderlustUser) -> Bool {
        !user.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            user.homeCountryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            user.profilePhotoData?.isEmpty == false
    }
}

// MARK: - Notification Permission Screen

private struct NotificationPermissionScreen: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 140, height: 140)

                    Image(systemName: "bell.badge.fill")
                        .wanderlustDecorativeFont(58)
                        .foregroundStyle(Color.orange)
                }

                VStack(spacing: 12) {
                    Text(WanderlustL10n.string("Enable Notifications", table: .settings))
                        .font(.title.bold())

                    Text(WanderlustL10n.string("Wanderlust can remind you to keep your trips and travel records up to date. You can use Wanderlust without notifications and change this later in iPhone Settings.", table: .settings))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 330)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                Button {
                    UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .badge, .sound]
                    ) { _, _ in
                        DispatchQueue.main.async {
                            onComplete()
                        }
                    }
                } label: {
                    Text(WanderlustL10n.string("Allow Notifications", table: .settings))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 32)

                Button(action: onComplete) {
                    Text(String(localized: "Not Now"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
            }
            .padding(.bottom, 52)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

// MARK: - Permission Explanation Screen

private struct PermissionExplanationScreen: View {
    let icon: String
    let color: Color
    let title: String
    let message: String
    let primaryTitle: String
    let secondaryTitle: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 140, height: 140)

                    Image(systemName: icon)
                        .wanderlustDecorativeFont(58)
                        .foregroundStyle(color)
                }

                VStack(spacing: 12) {
                    Text(title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: primaryAction) {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 32)

                Button(action: secondaryAction) {
                    Text(secondaryTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
            }
            .padding(.bottom, 52)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

// MARK: - Onboarding Pages

private struct OnboardingPageData {
    let icon: String
    let colors: [Color]
    let title: String
    let description: String
}

private let kOnboardingPages: [OnboardingPageData] = [
    OnboardingPageData(
        icon: "suitcase.fill",
        colors: [.blue, .indigo],
        title: WanderlustL10n.string("Keep Your Travels Together", table: .general),
        description: WanderlustL10n.string("Save the countries, cities, and dates from each trip.\nYour memories stay organized and easy to revisit.", table: .general)
    ),
    OnboardingPageData(
        icon: "map.fill",
        colors: [.teal, .blue],
        title: WanderlustL10n.string("Watch Your World Map Grow", table: .general),
        description: WanderlustL10n.string("Add a trip and each visited country fills with color.\nSee your journey expand at a glance.", table: .general)
    ),
    OnboardingPageData(
        icon: "book.closed.fill",
        colors: [.indigo, .purple],
        title: WanderlustL10n.string("Build Your Travel Passport", table: .general),
        description: WanderlustL10n.string("Collect a stamp for every country you visit.\nYour passport becomes richer with every journey.", table: .general)
    ),
    OnboardingPageData(
        icon: "airplane",
        colors: [.orange, .red],
        title: WanderlustL10n.string("Keep Every Flight in Order", table: .general),
        description: WanderlustL10n.string("Save airlines, airports, and flight numbers in one place.\nReview the routes you traveled on the map.", table: .general)
    ),
]

private struct OnboardingPagesView: View {
    let onGetStarted: () -> Void
    @State private var currentPage = 0

    private var pageColors: [Color] {
        kOnboardingPages[min(currentPage, kOnboardingPages.count - 1)].colors
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    pageColors.first?.opacity(0.18) ?? .blue.opacity(0.18),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .animation(.easeInOut(duration: 0.5), value: currentPage)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(kOnboardingPages.indices, id: \.self) { index in
                        OnboardingPageCard(data: kOnboardingPages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomBar
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 24) {
            HStack(spacing: 8) {
                ForEach(kOnboardingPages.indices, id: \.self) { index in
                    Capsule()
                        .fill(currentPage == index ? pageColors.first ?? .blue : Color.secondary.opacity(0.22))
                        .frame(width: currentPage == index ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }

            Button {
                if currentPage < kOnboardingPages.count - 1 {
                    withAnimation(.easeInOut) { currentPage += 1 }
                } else {
                    onGetStarted()
                }
            } label: {
                Text(currentPage < kOnboardingPages.count - 1 ? String(localized: "Next") : String(localized: "Get Started"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(pageColors.first ?? .blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .animation(.easeInOut(duration: 0.4), value: currentPage)
            }
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 52)
    }
}

private struct OnboardingPageCard: View {
    let data: OnboardingPageData

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: max(72, proxy.size.height * 0.20))

                VStack(spacing: 36) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: data.colors.map { $0.opacity(0.14) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 180, height: 180)

                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: data.colors.map { $0.opacity(0.28) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                            .frame(width: 180, height: 180)

                        Image(systemName: data.icon)
                            .wanderlustDecorativeFont(72, weight: .medium)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: data.colors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolRenderingMode(.multicolor)
                    }

                    VStack(spacing: 14) {
                        Text(data.title)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                            .frame(maxWidth: 350)
                            .padding(.horizontal, 24)

                        Text(data.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)
                            .frame(maxWidth: 340)
                            .padding(.horizontal, 24)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Auth Screen

private struct AuthScreen: View {
    let onAuthenticated: (WanderlustUser) -> Void
    let onBack: (() -> Void)?

    @StateObject private var authenticationStore = AuthenticationStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var didAppear = false
    @State private var authMode: AuthMode?

    var body: some View {
        ZStack {
            AuthWelcomeBackground(
                didAppear: didAppear,
                isProcessing: authenticationStore.isProcessing,
                onSignUp: {
                    authHaptic()
                    presentAuthCard(.signUp)
                },
                onLogin: {
                    authHaptic()
                    presentAuthCard(.login)
                }
            )

            if let authMode {
                Color.black.opacity(colorScheme == .dark ? 0.40 : 0.26)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        authHaptic()
                        dismissAuthCard()
                    }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AuthBottomCard(
                        mode: Binding(
                            get: { authMode },
                            set: { newMode in
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    self.authMode = newMode
                                }
                            }
                        ),
                        onClose: dismissAuthCard,
                        onAuthenticated: onAuthenticated
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.84)) {
                didAppear = true
            }
        }
        .safeAreaInset(edge: .top) {
            if let onBack {
                HStack {
                    Spacer()
                    Button {
                        authHaptic()
                        dismissAuthenticationKeyboard()
                        onBack()
                    } label: {
                        Image(systemName: "xmark")
                            .wanderlustFont(13, relativeTo: .footnote, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.black.opacity(0.22), in: Circle())
                    }
                    .buttonStyle(AuthSpringButtonStyle())
                    .accessibilityLabel(String(localized: "Close"))
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
        }
        .alert(
            WanderlustL10n.string("Account", table: .account),
            isPresented: Binding(
                get: { authenticationStore.authenticationError != nil },
                set: { if !$0 { authenticationStore.authenticationError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                authenticationStore.authenticationError = nil
            }
        } message: {
            Text(authenticationStore.authenticationError ?? "")
        }
    }

    private func presentAuthCard(_ mode: AuthMode) {
        dismissAuthenticationKeyboard()
        withAnimation(.spring(response: 0.50, dampingFraction: 0.80, blendDuration: 0.08)) {
            authMode = mode
        }
    }

    private func dismissAuthCard() {
        dismissAuthenticationKeyboard()
        withAnimation(.spring(response: 0.40, dampingFraction: 0.92, blendDuration: 0.04)) {
            authMode = nil
        }
    }
}

private struct AuthWelcomeBackground: View {
    let didAppear: Bool
    let isProcessing: Bool
    let onSignUp: () -> Void
    let onLogin: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AuthHeroBackground()
                .ignoresSafeArea()

            GeometryReader { proxy in
                let brandCenterY = min(max(proxy.size.height * 0.41, 286), proxy.size.height - 320)

                VStack(spacing: 24) {
                    WanderlustBrandMark(size: 96, cornerRadius: 24, shadowOpacity: 0)
                        .background {
                            RadialGradient(
                                colors: [
                                    iconGlowColor.opacity(colorScheme == .dark ? 0.28 : 0.30),
                                    iconGlowColor.opacity(0)
                                ],
                                center: .center,
                                startRadius: 34,
                                endRadius: 64
                            )
                            .frame(width: 124, height: 124)
                            .blur(radius: 8)
                        }
                        .scaleEffect(didAppear ? 1 : 0.94)

                    VStack(spacing: 8) {
                        WanderlustBrandTitle(size: 40, color: .white)
                        WanderlustBrandSubtitle(
                            color: colorScheme == .dark
                                ? .white.opacity(0.90)
                                : Color(red: 0.27, green: 0.22, blue: 0.18).opacity(0.82)
                        )
                        .shadow(
                            color: colorScheme == .dark ? .black.opacity(0.36) : .white.opacity(0.42),
                            radius: colorScheme == .dark ? 8 : 5,
                            y: colorScheme == .dark ? 3 : 1
                        )
                    }
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
                }
                .frame(maxWidth: .infinity)
                .position(x: proxy.size.width / 2, y: brandCenterY)
                .opacity(didAppear ? 1 : 0)
                .animation(.spring(response: 0.65, dampingFraction: 0.84), value: didAppear)
            }

            GeometryReader { proxy in
                let buttonCenterY = min(max(proxy.size.height * 0.80, 530), proxy.size.height - 118)

                VStack(spacing: 16) {
                    Button {
                        onSignUp()
                    } label: {
                        Text(AuthText.signUpTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .foregroundStyle(.white)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .blue.opacity(0.22), radius: 16, y: 8)
                    }
                    .buttonStyle(AuthSpringButtonStyle())

                    Button {
                        onLogin()
                    } label: {
                        Text(AuthText.loginTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .foregroundStyle(.white)
                            .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(.white.opacity(0.28), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                    }
                    .buttonStyle(AuthSpringButtonStyle())
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
                .position(x: proxy.size.width / 2, y: buttonCenterY)
                .opacity(didAppear ? 1 : 0)
                .disabled(isProcessing)
                .animation(.spring(response: 0.65, dampingFraction: 0.84), value: didAppear)
            }
        }
    }

    private var iconGlowColor: Color {
        colorScheme == .dark ? .black : .white
    }
}

enum AuthMode: Equatable {
    case login
    case signUp
    case passwordReset
}

private func authHaptic() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

private struct AuthSpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct AuthBottomCard: View {
    @Binding var mode: AuthMode
    let onClose: () -> Void
    let onAuthenticated: (WanderlustUser) -> Void

    @StateObject private var authenticationStore = AuthenticationStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isPasswordVisible = false
    @State private var didAttemptSubmit = false
    @State private var didSendPasswordReset = false
    @GestureState private var dragTranslation: CGFloat = 0
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password, confirmPassword
    }

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmailValid: Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return cleanEmail.range(of: pattern, options: .regularExpression) != nil
    }

    private var isPasswordValid: Bool {
        switch mode {
        case .login:
            return !password.isEmpty
        case .signUp:
            return WanderlustPasswordPolicy.isValid(password)
        case .passwordReset:
            return true
        }
    }

    private var canSubmit: Bool {
        guard !authenticationStore.isProcessing, isEmailValid else { return false }
        switch mode {
        case .login:
            return isPasswordValid
        case .signUp:
            return isPasswordValid && !confirmPassword.isEmpty && password == confirmPassword
        case .passwordReset:
            return true
        }
    }

    private var cardMaxHeight: CGFloat {
        switch mode {
        case .login:
            return 600
        case .signUp:
            return 690
        case .passwordReset:
            return 300
        }
    }

    private var keyboardContentBottomPadding: CGFloat {
        if focusedField == nil { return 28 }
        return mode == .passwordReset ? 12 : 124
    }

    private var rubberBandDragOffset: CGFloat {
        let distance = max(dragTranslation, 0)
        let resistanceStart: CGFloat = 130
        guard distance > resistanceStart else { return distance }
        return resistanceStart + (distance - resistanceStart) * 0.34
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 42, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        fields
                        submitButton
                        if mode != .passwordReset {
                            AuthOrDivider(label: AuthText.or)
                            socialButtons
                        }
                        footerLink
                    }
                    .id(mode)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
                    .padding(.bottom, keyboardContentBottomPadding)
                    .frame(maxWidth: 430)
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.22), value: mode)
                    .onChange(of: focusedField) { _, field in
                        guard let field else { return }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 120_000_000)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(field, anchor: .center)
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: cardMaxHeight)
            }
        }
        .background(cardBackground)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 36, topTrailingRadius: 36, style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.38 : 0.18), radius: 26, y: -10)
        .frame(maxWidth: .infinity)
        .offset(y: rubberBandDragOffset)
        .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.86), value: dragTranslation)
        .simultaneousGesture(
            DragGesture()
                .updating($dragTranslation) { value, state, _ in
                    state = max(value.translation.height, 0)
                }
                .onEnded { value in
                    if value.translation.height > 90 || value.predictedEndTranslation.height > 180 {
                        authHaptic()
                        onClose()
                    }
                }
        )
        .alert(
            WanderlustL10n.string("Account", table: .account),
            isPresented: Binding(
                get: { authenticationStore.authenticationError != nil },
                set: { if !$0 { authenticationStore.authenticationError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                authenticationStore.authenticationError = nil
            }
        } message: {
            Text(authenticationStore.authenticationError ?? "")
        }
        .alert(AuthText.passwordResetSentTitle, isPresented: $didSendPasswordReset) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(AuthText.passwordResetSentMessage)
        }
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color(.systemBackground)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(titleText)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .contentTransition(.opacity)
            Spacer(minLength: 12)
            Button {
                authHaptic()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(AuthSpringButtonStyle())
            .accessibilityLabel(String(localized: "Close"))
        }
    }

    private var titleText: String {
        switch mode {
        case .login:
            return AuthText.loginTitle
        case .signUp:
            return AuthText.signUpTitle
        case .passwordReset:
            return AuthText.passwordResetTitle
        }
    }

    private var fields: some View {
        VStack(spacing: 12) {
            AuthInputField(
                text: $email,
                placeholder: AuthText.email,
                systemImage: "envelope",
                keyboardType: .default,
                textContentType: .emailAddress,
                isFocused: focusedField == .email
            )
            .focused($focusedField, equals: .email)
            .id(Field.email)
            .submitLabel(mode == .passwordReset ? .done : .next)
            .onSubmit {
                if mode == .passwordReset {
                    focusedField = nil
                } else {
                    focusedField = .password
                }
            }

            if mode != .passwordReset {
                AuthPasswordField(
                    text: $password,
                    placeholder: AuthText.password,
                    isVisible: $isPasswordVisible,
                    textContentType: mode == .login ? .password : .newPassword,
                    isFocused: focusedField == .password
                )
                .focused($focusedField, equals: .password)
                .id(Field.password)
                .submitLabel(mode == .login ? .done : .next)
                .onSubmit {
                    if mode == .login {
                        focusedField = nil
                    } else {
                        focusedField = .confirmPassword
                    }
                }
            }

            if mode == .signUp {
                AuthPasswordField(
                    text: $confirmPassword,
                    placeholder: AuthText.confirmPassword,
                    isVisible: $isPasswordVisible,
                    textContentType: .newPassword,
                    isFocused: focusedField == .confirmPassword
                )
                .focused($focusedField, equals: .confirmPassword)
                .id(Field.confirmPassword)
                .submitLabel(.done)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onSubmit { focusedField = nil }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if mode == .login {
                Button {
                    authHaptic()
                    openPasswordReset()
                } label: {
                    Text(AuthText.forgotPassword)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .buttonStyle(AuthSpringButtonStyle())
                .disabled(authenticationStore.isProcessing)
            }
        }
    }

    private var errorText: String? {
        guard didAttemptSubmit else { return nil }
        if !isEmailValid { return WanderlustL10n.string("Enter a valid email address.", table: .errors) }
        if mode == .signUp, !WanderlustPasswordPolicy.isValid(password) {
            return WanderlustPasswordPolicy.requirementMessage
        }
        if mode == .signUp, password != confirmPassword {
            return WanderlustL10n.string("Passwords do not match.", table: .errors)
        }
        return nil
    }

    private var submitButton: some View {
        Button {
            if canSubmit {
                authHaptic()
            }
            submit()
        } label: {
            HStack(spacing: 8) {
                if authenticationStore.isProcessing {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }
                Text(submitButtonTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: canSubmit
                        ? [Color.blue.opacity(0.96), Color.blue]
                        : [Color.secondary.opacity(0.30), Color.secondary.opacity(0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: (canSubmit ? Color.blue : Color.black).opacity(canSubmit ? 0.18 : 0.08), radius: 12, y: 6)
        }
        .buttonStyle(AuthSpringButtonStyle())
        .disabled(!canSubmit)
    }

    private var submitButtonTitle: String {
        switch mode {
        case .login:
            return AuthText.loginTitle
        case .signUp:
            return AuthText.signUpSubmitTitle
        case .passwordReset:
            return AuthText.sendPasswordReset
        }
    }

    private var socialButtons: some View {
        HStack(spacing: 14) {
            AuthIconButton(kind: .apple, isDisabled: authenticationStore.isProcessing) {
                authHaptic()
                signInWithApple()
            }
            AuthIconButton(kind: .google, isDisabled: authenticationStore.isProcessing) {
                authHaptic()
                signInWithGoogle()
            }
        }
    }

    private var footerLink: some View {
        Button {
            authHaptic()
            switchMode()
        } label: {
            HStack(spacing: 4) {
                if mode == .login {
                    Text(AuthText.noAccountPrefix)
                        .foregroundStyle(.secondary)
                    Text(AuthText.createAccountInline)
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                } else if mode == .signUp {
                    Text(AuthText.hasAccountPrefix)
                        .foregroundStyle(.secondary)
                    Text(AuthText.loginInline)
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                } else {
                    Text(AuthText.backToLogin)
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
            .font(.footnote)
            .multilineTextAlignment(.center)
        }
        .buttonStyle(AuthSpringButtonStyle())
        .disabled(authenticationStore.isProcessing)
    }

    private func switchMode() {
        didAttemptSubmit = false
        authenticationStore.authenticationError = nil
        focusedField = nil
        dismissAuthenticationKeyboard()
        withAnimation(.easeInOut(duration: 0.22)) {
            switch mode {
            case .login:
                mode = .signUp
            case .signUp, .passwordReset:
                mode = .login
            }
        }
    }

    private func openPasswordReset() {
        didAttemptSubmit = false
        authenticationStore.authenticationError = nil
        password = ""
        confirmPassword = ""
        focusedField = .email
        withAnimation(.easeInOut(duration: 0.22)) {
            mode = .passwordReset
        }
    }

    private func submit() {
        didAttemptSubmit = true
        guard canSubmit else { return }
        focusedField = nil
        dismissAuthenticationKeyboard()
        Task {
            let user: WanderlustUser?
            switch mode {
            case .login:
                user = await authenticationStore.signIn(email: cleanEmail, password: password)
            case .signUp:
                user = await authenticationStore.createAccount(
                    name: "",
                    email: cleanEmail,
                    password: password,
                    homeCountryISO2: nil,
                    profilePhotoData: nil
                )
            case .passwordReset:
                await MainActor.run {
                    sendPasswordReset()
                }
                return
            }
            if let user {
                await MainActor.run {
                    onAuthenticated(user)
                }
            }
        }
    }

    private func signInWithApple() {
        focusedField = nil
        dismissAuthenticationKeyboard()
        Task {
            if let user = await authenticationStore.signInWithApple() {
                await MainActor.run {
                    onAuthenticated(user)
                }
            }
        }
    }

    private func signInWithGoogle() {
        focusedField = nil
        dismissAuthenticationKeyboard()
        Task {
            if let user = await authenticationStore.signInWithGoogle() {
                await MainActor.run {
                    onAuthenticated(user)
                }
            }
        }
    }

    private func sendPasswordReset() {
        didAttemptSubmit = true
        guard isEmailValid, !authenticationStore.isProcessing else { return }
        focusedField = nil
        dismissAuthenticationKeyboard()
        Task {
            if await authenticationStore.resetPassword(email: cleanEmail) {
                await MainActor.run {
                    didSendPasswordReset = true
                }
            }
        }
    }
}

private struct AuthInputField: View {
    @Binding var text: String
    let placeholder: String
    let systemImage: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var isFocused = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isFocused ? Color.blue : Color.secondary)
                .frame(width: 22)
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(fieldBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(isFocused ? Color.blue.opacity(0.42) : Color.clear, lineWidth: 1.2)
        }
        .shadow(color: isFocused ? Color.blue.opacity(0.14) : Color.black.opacity(0.03), radius: isFocused ? 12 : 5, y: isFocused ? 5 : 2)
        .scaleEffect(isFocused ? 1.012 : 1)
        .offset(y: isFocused ? -1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isFocused)
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? Color(.tertiarySystemBackground) : Color(.systemGray6)
    }
}

private struct AuthPasswordField: View {
    @Binding var text: String
    let placeholder: String
    @Binding var isVisible: Bool
    var textContentType: UITextContentType?
    var keyboardType: UIKeyboardType = .asciiCapable
    var isFocused = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isFocused ? Color.blue : Color.secondary)
                .frame(width: 22)

            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body)

            Button {
                authHaptic()
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(AuthSpringButtonStyle())
            .accessibilityLabel(isVisible ? AuthText.hidePassword : AuthText.showPassword)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 56)
        .background(fieldBackground, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(isFocused ? Color.blue.opacity(0.42) : Color.clear, lineWidth: 1.2)
        }
        .shadow(color: isFocused ? Color.blue.opacity(0.14) : Color.black.opacity(0.03), radius: isFocused ? 12 : 5, y: isFocused ? 5 : 2)
        .scaleEffect(isFocused ? 1.012 : 1)
        .offset(y: isFocused ? -1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isFocused)
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? Color(.tertiarySystemBackground) : Color(.systemGray6)
    }
}

private enum AuthText {
    private static var lang: String {
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

    static var loginTitle: String {
        switch lang {
        case "ja": return "ログイン"
        case "de": return "Einloggen"
        default: return "Log In"
        }
    }

    static var signUpTitle: String {
        switch lang {
        case "ja": return "アカウント登録"
        case "de": return "Registrieren"
        default: return "Sign Up"
        }
    }

    static var signUpSubmitTitle: String {
        switch lang {
        case "ja": return "登録する"
        case "de": return "Registrieren"
        default: return "Sign Up"
        }
    }

    static var passwordResetTitle: String {
        switch lang {
        case "ja": return "パスワードを再設定"
        case "de": return "Passwort zurücksetzen"
        default: return "Reset Password"
        }
    }

    static var loginSubtitle: String {
        switch lang {
        case "ja": return "Wanderlustに戻って、旅の記録を続けましょう。"
        case "de": return "Melde dich an und setze dein Reisetagebuch fort."
        default: return "Sign in to continue your travel journal."
        }
    }

    static var signUpSubtitle: String {
        switch lang {
        case "ja": return "メールアドレスとパスワードで始められます。"
        case "de": return "Starte mit deiner E-Mail-Adresse und einem Passwort."
        default: return "Start with your email address and password."
        }
    }

    static var email: String {
        switch lang {
        case "ja": return "メールアドレス"
        case "de": return "E-Mail-Adresse"
        default: return "Email Address"
        }
    }

    static var password: String {
        switch lang {
        case "ja": return "パスワード"
        case "de": return "Passwort"
        default: return "Password"
        }
    }

    static var confirmPassword: String {
        switch lang {
        case "ja": return "パスワードを確認"
        case "de": return "Passwort bestätigen"
        default: return "Confirm Password"
        }
    }

    static var forgotPassword: String {
        switch lang {
        case "ja": return "パスワードをお忘れですか？"
        case "de": return "Passwort vergessen?"
        default: return "Forgot Password?"
        }
    }

    static var sendPasswordReset: String {
        switch lang {
        case "ja": return "再設定メールを送信"
        case "de": return "E-Mail senden"
        default: return "Send Reset Email"
        }
    }

    static var backToLogin: String {
        switch lang {
        case "ja": return "ログインに戻る"
        case "de": return "Zurück zum Login"
        default: return "Back to Log In"
        }
    }

    static var or: String {
        switch lang {
        case "ja": return "または"
        case "de": return "oder"
        default: return "or"
        }
    }

    static var noAccountPrefix: String {
        switch lang {
        case "ja": return "アカウントをお持ちでないですか？"
        case "de": return "Noch kein Konto?"
        default: return "Don't have an account?"
        }
    }

    static var createAccountInline: String {
        switch lang {
        case "ja": return "アカウント登録"
        case "de": return "Registrieren"
        default: return "Sign Up"
        }
    }

    static var hasAccountPrefix: String {
        switch lang {
        case "ja": return "すでにアカウントをお持ちですか？"
        case "de": return "Du hast bereits ein Konto?"
        default: return "Already have an account?"
        }
    }

    static var loginInline: String {
        switch lang {
        case "ja": return "ログイン"
        case "de": return "Einloggen"
        default: return "Log In"
        }
    }

    static var showPassword: String {
        switch lang {
        case "ja": return "パスワードを表示"
        case "de": return "Passwort anzeigen"
        default: return "Show Password"
        }
    }

    static var hidePassword: String {
        switch lang {
        case "ja": return "パスワードを非表示"
        case "de": return "Passwort ausblenden"
        default: return "Hide Password"
        }
    }

    static var passwordResetSentTitle: String {
        switch lang {
        case "ja": return "メールを送信しました"
        case "de": return "E-Mail gesendet"
        default: return "Email Sent"
        }
    }

    static var passwordResetSentMessage: String {
        switch lang {
        case "ja": return "パスワード再設定用のメールを確認してください。"
        case "de": return "Bitte prüfe deine E-Mail zum Zurücksetzen des Passworts."
        default: return "Check your email for password reset instructions."
        }
    }
}

private struct AuthHeroBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.025, green: 0.040, blue: 0.070),
                        Color(red: 0.090, green: 0.105, blue: 0.145),
                        Color(red: 0.215, green: 0.120, blue: 0.095),
                        Color(red: 0.050, green: 0.060, blue: 0.070)
                    ]
                    : [
                        Color(red: 0.330, green: 0.570, blue: 0.780),
                        Color(red: 0.690, green: 0.760, blue: 0.830),
                        Color(red: 0.970, green: 0.575, blue: 0.335),
                        Color(red: 0.365, green: 0.395, blue: 0.400)
                    ],
                startPoint: .top,
                endPoint: .bottom
            )

            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height

                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.55))
                    path.addCurve(
                        to: CGPoint(x: width, y: height * 0.52),
                        control1: CGPoint(x: width * 0.25, y: height * 0.48),
                        control2: CGPoint(x: width * 0.62, y: height * 0.60)
                    )
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill((colorScheme == .dark ? Color.black : Color(red: 0.24, green: 0.22, blue: 0.18)).opacity(colorScheme == .dark ? 0.24 : 0.10))

                Path { path in
                    path.move(to: CGPoint(x: -width * 0.1, y: height * 0.63))
                    path.addCurve(
                        to: CGPoint(x: width * 1.1, y: height * 0.60),
                        control1: CGPoint(x: width * 0.23, y: height * 0.57),
                        control2: CGPoint(x: width * 0.74, y: height * 0.68)
                    )
                    path.addLine(to: CGPoint(x: width * 1.1, y: height))
                    path.addLine(to: CGPoint(x: -width * 0.1, y: height))
                    path.closeSubpath()
                }
                .fill((colorScheme == .dark ? Color.black : Color(red: 0.17, green: 0.20, blue: 0.18)).opacity(colorScheme == .dark ? 0.34 : 0.18))
            }
        }
    }
}

private struct SocialSignInLabel<Icon: View, Title: View>: View {
    let foregroundStyle: Color
    let backgroundStyle: AnyShapeStyle
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var title: () -> Title

    var body: some View {
        HStack(spacing: 8) {
            icon()
                .frame(width: 22, height: 22, alignment: .center)
            title()
                .wanderlustFont(15, relativeTo: .subheadline, weight: .semibold)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
        .foregroundStyle(foregroundStyle)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct AuthOrDivider: View {
    var label: String = String(localized: "or")

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)
        }
    }
}

private enum AuthIconButtonKind {
    case apple, google
}

private struct AuthIconButton: View {
    let kind: AuthIconButtonKind
    var isDisabled = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Group {
                switch kind {
                case .apple:
                    Image(systemName: "apple.logo")
                        .wanderlustFont(22, relativeTo: .title2, weight: .medium)
                case .google:
                    Image("GoogleGLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 21, height: 21)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(foregroundColor)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 8, y: 3)
            .opacity(isDisabled ? 0.55 : 1)
            .scaleEffect(isDisabled ? 0.98 : 1)
        }
        .buttonStyle(AuthSpringButtonStyle())
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private var foregroundColor: Color {
        switch kind {
        case .apple:
            return colorScheme == .dark ? .white : .black
        case .google:
            return .primary
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.58)
    }

    private var accessibilityLabel: String {
        switch kind {
        case .apple:
            return WanderlustL10n.string("Continue with Apple", table: .account, fallback: "Continue with Apple")
        case .google:
            return WanderlustL10n.string("Continue with Google", table: .account, fallback: "Continue with Google")
        }
    }
}

private struct AppleSignInButtonLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AuthButtonAlignedLabel(
            foregroundStyle: .white,
            backgroundStyle: AnyShapeStyle(colorScheme == .dark ? Color(white: 0.20) : .black)
        ) {
            Image(systemName: "apple.logo")
                .wanderlustFont(20, relativeTo: .title3, weight: .medium)
                .accessibilityHidden(true)
        } title: {
            Text(WanderlustL10n.string("Continue with Apple", table: .account, fallback: "Continue with Apple"))
        }
    }
}

private struct GoogleSignInButtonLabel: View {
    let titleKey: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AuthButtonAlignedLabel(
            foregroundStyle: colorScheme == .dark ? .white : Color(red: 0.12, green: 0.12, blue: 0.12),
            backgroundStyle: AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.15) : .white),
            strokeColor: colorScheme == .dark ? Color.white.opacity(0.10) : Color.primary.opacity(0.12)
        ) {
            googleIcon
        } title: {
            Text(WanderlustL10n.string(titleKey, table: .account))
        }
    }

    @ViewBuilder
    private var googleIcon: some View {
        #if canImport(GoogleSignInSwift)
        GoogleSignInButton(scheme: .light, style: .icon, state: .normal) {}
            .allowsHitTesting(false)
            .frame(width: 24, height: 24)
            .scaleEffect(1.08)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityHidden(true)
        #else
        Text(verbatim: "G")
            .font(.headline.weight(.bold))
            .foregroundStyle(.blue)
            .accessibilityHidden(true)
        #endif
    }
}

private struct EmailSignUpButtonLabel: View {
    let titleKey: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AuthButtonAlignedLabel(
            foregroundStyle: colorScheme == .dark ? .white : Color(red: 0.20, green: 0.14, blue: 0.08),
            backgroundStyle: AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.15) : Color.white.opacity(0.62))
        ) {
            Image(systemName: "envelope.fill")
                .wanderlustFont(19, relativeTo: .title3, weight: .semibold)
                .accessibilityHidden(true)
        } title: {
            Text(WanderlustL10n.string(titleKey, table: .account))
        }
    }
}

private struct AuthButtonAlignedLabel<Icon: View, Title: View>: View {
    let foregroundStyle: Color
    let backgroundStyle: AnyShapeStyle
    var strokeColor: Color = .clear
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var title: () -> Title

    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            icon()
                .frame(width: 24, height: 24, alignment: .center)
            title()
                .wanderlustFont(17, relativeTo: .body, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(foregroundStyle)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        }
    }
}

// MARK: - Email Registration Screen

private struct EmailRegistrationScreen: View {
    @Binding var username: String
    @Binding var email: String
    @Binding var homeCountry: String
    @Binding var profilePhotoData: Data
    let onBack: () -> Void
    let onContinue: () -> Void
    let onGoogleComplete: (WanderlustUser) -> Void
    let onAppleComplete: (WanderlustUser) -> Void

    @StateObject private var authenticationStore = AuthenticationStore.shared
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var suggestions: [Country] = []
    @State private var didAttemptContinue = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, email, password, confirmPassword, country
    }

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanCountry: String {
        homeCountry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedCountry: Country? {
        GeoJSONLoader.shared.country(withISOCode: cleanCountry) ??
            GeoJSONLoader.shared.country(named: cleanCountry)
    }

    private var countryEntryText: Binding<String> {
        Binding(
            get: {
                selectedCountry?.displayName ?? homeCountry
            },
            set: { newValue in
                homeCountry = newValue
            }
        )
    }

    private var isEmailValid: Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return cleanEmail.range(of: pattern, options: .regularExpression) != nil
    }

    private var isPasswordValid: Bool {
        WanderlustPasswordPolicy.isValid(password)
    }

    private var passwordsMatch: Bool {
        !confirmPassword.isEmpty && password == confirmPassword
    }

    private var isCountryValid: Bool {
        guard let selectedCountry else { return false }
        return selectedCountry.isoCode == cleanCountry.uppercased() ||
            selectedCountry.name.localizedCaseInsensitiveCompare(cleanCountry) == .orderedSame ||
            selectedCountry.displayName.localizedCaseInsensitiveCompare(cleanCountry) == .orderedSame
    }

    private var canContinue: Bool {
        isEmailValid && isPasswordValid && passwordsMatch
    }

    private var keyboardSpacerHeight: CGFloat {
        focusedField == nil ? 0 : 96
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 28) {
                        Text(WanderlustL10n.string("Create Your Account", table: .account))
                            .font(.title.bold())
                            .multilineTextAlignment(.center)

                        VStack(spacing: 18) {

                        registrationField(
                            title: WanderlustL10n.string("Email", table: .account),
                            error: didAttemptContinue && !cleanEmail.isEmpty && !isEmailValid
                                ? WanderlustL10n.string("Invalid email address.", table: .errors)
                                : didAttemptContinue && cleanEmail.isEmpty ? WanderlustL10n.string("Email is required.", table: .errors) : nil
                        ) {
                            TextField(WanderlustL10n.string("email@example.com", table: .account), text: $email)
                                .keyboardType(.default)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.emailAddress)
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                        }
                        .id(Field.email)

                        registrationField(
                            title: WanderlustL10n.string("Password", table: .account),
                            error: !password.isEmpty && !isPasswordValid
                                ? WanderlustPasswordPolicy.requirementMessage
                                : didAttemptContinue && password.isEmpty ? WanderlustL10n.string("Password is required.", table: .errors) : nil
                        ) {
                            SecureField(WanderlustL10n.string("Password requirement placeholder", table: .account, fallback: "8+ chars, A-Z, a-z, 0-9"), text: $password)
                                .keyboardType(.asciiCapable)
                                .textContentType(.newPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .password)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .confirmPassword }
                        }
                        .id(Field.password)

                        registrationField(
                            title: WanderlustL10n.string("Confirm Password", table: .account),
                            error: !confirmPassword.isEmpty && !passwordsMatch
                                ? WanderlustL10n.string("Passwords do not match.", table: .errors)
                                : didAttemptContinue && confirmPassword.isEmpty ? WanderlustL10n.string("Password confirmation is required.", table: .errors, fallback: "Password confirmation is required.") : nil
                        ) {
                            SecureField(WanderlustL10n.string("Confirm Password", table: .account), text: $confirmPassword)
                                .keyboardType(.asciiCapable)
                                .textContentType(.newPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .confirmPassword)
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }
                        }
                        .id(Field.confirmPassword)

                        Button {
                            createEmailAccount()
                        } label: {
                            HStack {
                                if authenticationStore.isProcessing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(WanderlustL10n.string("Sign Up", table: .account, fallback: "Sign Up"))
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .foregroundStyle(.white)
                            .background(canContinue ? Color.blue : Color.secondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(!canContinue || authenticationStore.isProcessing)

                        AuthOrDivider()
                            .padding(.vertical, 2)

                        HStack(spacing: 14) {
                            AuthIconButton(kind: .apple) {
                                signInWithApple()
                            }
                            AuthIconButton(kind: .google) {
                                signInWithGoogle()
                            }
                        }

                        Button {
                            focusedField = nil
                            onBack()
                        } label: {
                            Text(WanderlustL10n.string("Already have an account? Log In", table: .account, fallback: "Already have an account? Log In"))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        .padding(.top, 4)
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                    .onTapGesture {
                        focusedField = nil
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear
                        .frame(height: keyboardSpacerHeight)
                }
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(field, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle(WanderlustL10n.string("Create Your Account", table: .account))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        focusedField = nil
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(WanderlustL10n.string("Back", table: .trips))
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .gesture(
            DragGesture()
                .onEnded { value in
                    guard value.startLocation.x < 36,
                          value.translation.width > 80,
                          abs(value.translation.height) < 60 else {
                        return
                    }
                    focusedField = nil
                    onBack()
                }
        )
        .alert(
            WanderlustL10n.string("Account", table: .account),
            isPresented: Binding(
                get: { authenticationStore.authenticationError != nil },
                set: { if !$0 { authenticationStore.authenticationError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                authenticationStore.authenticationError = nil
            }
        } message: {
            Text(authenticationStore.authenticationError ?? "")
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear { GeoJSONLoader.shared.loadIfNeeded() }
    }

    private func createEmailAccount() {
        didAttemptContinue = true
        guard canContinue else { return }
        focusedField = nil
        dismissAuthenticationKeyboard()
        Task {
            let user = await authenticationStore.createAccount(
                name: "",
                email: cleanEmail,
                password: password,
                homeCountryISO2: nil,
                profilePhotoData: nil
            )
            guard user != nil else { return }
            await MainActor.run {
                focusedField = nil
                dismissAuthenticationKeyboard()
                onContinue()
            }
        }
    }

    private func signInWithApple() {
        focusedField = nil
        dismissAuthenticationKeyboard()
        Task {
            if let user = await authenticationStore.signInWithApple() {
                await MainActor.run {
                    dismissAuthenticationKeyboard()
                    onAppleComplete(user)
                }
            }
        }
    }

    private func signInWithGoogle() {
        focusedField = nil
        dismissAuthenticationKeyboard()
        Task {
            if let user = await authenticationStore.signInWithGoogle() {
                await MainActor.run {
                    dismissAuthenticationKeyboard()
                    onGoogleComplete(user)
                }
            }
        }
    }

    private var countryField: some View {
        registrationField(
            title: WanderlustL10n.string("Home Country", table: .account),
            error: didAttemptContinue && cleanCountry.isEmpty
                ? WanderlustL10n.string("Home Country is required.", table: .errors)
                : didAttemptContinue && !isCountryValid ? WanderlustL10n.string("Select a country from the list.", table: .errors) : nil
        ) {
            TextField(String(localized: "Japan, France, Germany…"), text: countryEntryText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .country)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .onChange(of: homeCountry) { _, _ in updateSuggestions() }

            if !suggestions.isEmpty {
                countrySuggestions
            }
        }
    }

    private var countrySuggestions: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { country in
                Button {
                    homeCountry = country.isoCode
                    suggestions = []
                    focusedField = nil
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flagEmoji).font(.title3)
                        Text(country.displayName).foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                if country.id != suggestions.last?.id {
                    Divider().padding(.leading, 50)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func registrationField<Content: View>(
        title: String,
        error: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func updateSuggestions() {
        let q = cleanCountry
        guard !q.isEmpty else { suggestions = []; return }
        if let exact = GeoJSONLoader.shared.country(withISOCode: q) ?? GeoJSONLoader.shared.country(named: q),
           exact.displayName.localizedCaseInsensitiveCompare(q) == .orderedSame || exact.isoCode == q.uppercased() {
            suggestions = []
            return
        }
        suggestions = GeoJSONLoader.shared.searchCountries(query: q, limit: 5)
    }
}

private struct EmailLoginScreen: View {
    let onBack: () -> Void
    let onForgotPassword: () -> Void
    let onComplete: () -> Void
    let onGoogleComplete: (WanderlustUser) -> Void
    let onAppleComplete: (WanderlustUser) -> Void

    @AppStorage("atlas.username") private var username = ""
    @AppStorage("atlas.email") private var storedEmail = ""
    @AppStorage("atlas.homeCountry") private var homeCountry = ""
    @AppStorage("atlas.profilePhotoData") private var profilePhotoData = Data()

    @StateObject private var authenticationStore = AuthenticationStore.shared
    @State private var email = ""
    @State private var password = ""
    @State private var didAttemptLogin = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmailValid: Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return cleanEmail.range(of: pattern, options: .regularExpression) != nil
    }

    private var canLogin: Bool {
        isEmailValid && !password.isEmpty && !authenticationStore.isProcessing
    }

    private var keyboardSpacerHeight: CGFloat {
        focusedField == nil ? 0 : 96
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        WanderlustBrandMark(size: 72, cornerRadius: 18, shadowOpacity: 0.12)

                        VStack(spacing: 18) {
                        Text(WanderlustL10n.string("Log In", table: .account))
                            .font(.title2.bold())

                        VStack(spacing: 12) {
                            TextField(WanderlustL10n.string("Email", table: .account), text: $email)
                                .keyboardType(.default)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.emailAddress)
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .password }
                                .id(Field.email)
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            SecureField(WanderlustL10n.string("Password", table: .account), text: $password)
                                .keyboardType(.asciiCapable)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .password)
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }
                                .id(Field.password)
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            if didAttemptLogin && !isEmailValid {
                                Text(WanderlustL10n.string("Enter a valid email address.", table: .errors))
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        Button(WanderlustL10n.string("Forgot Password?", table: .account)) {
                            focusedField = nil
                            onForgotPassword()
                        }
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        Button {
                            logInWithEmail()
                        } label: {
                            HStack {
                                if authenticationStore.isProcessing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(WanderlustL10n.string("Log In", table: .account))
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .foregroundStyle(.white)
                            .background(canLogin ? Color.blue : Color.secondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(!canLogin)

                        AuthOrDivider()

                        HStack(spacing: 14) {
                            AuthIconButton(kind: .apple) {
                                signInWithApple()
                            }
                            AuthIconButton(kind: .google) {
                                signInWithGoogle()
                            }
                        }

                        Button {
                            focusedField = nil
                            onBack()
                        } label: {
                            Text(WanderlustL10n.string("Don't have an account? Sign Up", table: .account, fallback: "Don't have an account? Sign Up"))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                    .padding(.horizontal, 24)
                    .padding(.top, 42)
                    .padding(.bottom, 36)
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear
                        .frame(height: keyboardSpacerHeight)
                }
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(field, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle(WanderlustL10n.string("Log In", table: .account))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        focusedField = nil
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(WanderlustL10n.string("Back", table: .trips))
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .alert(
            WanderlustL10n.string("Account", table: .account),
            isPresented: Binding(
                get: { authenticationStore.authenticationError != nil },
                set: { if !$0 { authenticationStore.authenticationError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                authenticationStore.authenticationError = nil
            }
        } message: {
            Text(authenticationStore.authenticationError ?? "")
        }
    }

    private func logInWithEmail() {
        didAttemptLogin = true
        guard canLogin else { return }
        focusedField = nil
        dismissAuthenticationKeyboard()
        Task {
            if let user = await authenticationStore.signIn(email: cleanEmail, password: password) {
                username = user.name
                storedEmail = user.email
                homeCountry = user.homeCountryISO2 ?? ""
                if let photoData = user.profilePhotoData {
                    profilePhotoData = photoData
                }
                await MainActor.run {
                    focusedField = nil
                    dismissAuthenticationKeyboard()
                    onComplete()
                }
            }
        }
    }

    private func signInWithApple() {
        focusedField = nil
        dismissAuthenticationKeyboard()
        Task {
            if let user = await authenticationStore.signInWithApple() {
                await MainActor.run {
                    dismissAuthenticationKeyboard()
                    onAppleComplete(user)
                }
            }
        }
    }

    private func signInWithGoogle() {
        focusedField = nil
        dismissAuthenticationKeyboard()
        Task {
            if let user = await authenticationStore.signInWithGoogle() {
                await MainActor.run {
                    dismissAuthenticationKeyboard()
                    onGoogleComplete(user)
                }
            }
        }
    }
}

private struct PasswordResetScreen: View {
    let onBack: () -> Void

    @StateObject private var authenticationStore = AuthenticationStore.shared
    @State private var email = ""
    @State private var didSend = false
    @FocusState private var isFocused: Bool

    private var cleanEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        cleanEmail.contains("@") && !authenticationStore.isProcessing
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(WanderlustL10n.string("Email", table: .account), text: $email)
                        .keyboardType(.default)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                } footer: {
                    Text(WanderlustL10n.string("If an account exists for this email, Wanderlust will send password reset instructions.", table: .account))
                }

                Section {
                    Button {
                        guard canSend else { return }
                        isFocused = false
                        dismissAuthenticationKeyboard()
                        Task {
                            let didReset = await authenticationStore.resetPassword(email: cleanEmail)
                            if didReset {
                                await MainActor.run {
                                    isFocused = false
                                    dismissAuthenticationKeyboard()
                                }
                                didSend = true
                            }
                        }
                    } label: {
                        HStack {
                            if authenticationStore.isProcessing {
                                ProgressView()
                            }
                            Text(WanderlustL10n.string("Send Reset Email", table: .account))
                        }
                    }
                    .disabled(!canSend)
                }

                if didSend {
                    Section {
                        Text(WanderlustL10n.string("Reset instructions were sent. Check your email, then return to log in.", table: .account))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(WanderlustL10n.string("Reset Password", table: .account))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isFocused = false
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(WanderlustL10n.string("Back", table: .trips))
                }
            }
        }
        .alert(
            WanderlustL10n.string("Account", table: .account),
            isPresented: Binding(
                get: { authenticationStore.authenticationError != nil },
                set: { if !$0 { authenticationStore.authenticationError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {
                authenticationStore.authenticationError = nil
            }
        } message: {
            Text(authenticationStore.authenticationError ?? "")
        }
    }
}

// MARK: - Onboarding Profile Photo

private struct OnboardingProfilePhotoPicker: View {
    @Binding var profilePhotoData: Data

    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showDeniedAlert = false
    @State private var selectedImage: UIImage?
    @State private var showCropper = false
    @State private var isLoadingPhoto = false
    @State private var photoLoadTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Button {
                requestPhotoSelection()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let image = UIImage(data: profilePhotoData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(Color.blue)
                                .padding(10)
                        }
                    }
                    .frame(width: 92, height: 92)
                    .clipShape(Circle())
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())

                    Image(systemName: "camera.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Color.blue, in: Circle())

                    if isLoadingPhoto {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 92, height: 92)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WanderlustL10n.string("Profile Photo", table: .account))
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) {
            loadSelectedPhoto()
        }
        .onDisappear {
            photoLoadTask?.cancel()
            photoLoadTask = nil
        }
        .sheet(isPresented: $showCropper) {
            if let selectedImage {
                PhotoCropView(image: selectedImage) { croppedImage in
                    if let data = croppedImage.jpegData(compressionQuality: 0.84) {
                        profilePhotoData = data
                    }
                    self.selectedImage = nil
                    showCropper = false
                } onCancel: {
                    self.selectedImage = nil
                    showCropper = false
                }
            }
        }
        .alert(
            WanderlustL10n.string("Photos Access Needed", table: .errors),
            isPresented: $showDeniedAlert
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
    }

    private func requestPhotoSelection() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            showPicker = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    if status == .authorized || status == .limited {
                        showPicker = true
                    } else {
                        showDeniedAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showDeniedAlert = true
        @unknown default:
            showDeniedAlert = true
        }
    }

    private func loadSelectedPhoto() {
        guard let pickerItem else { return }
        photoLoadTask?.cancel()
        isLoadingPhoto = true
        photoLoadTask = Task {
            do {
                guard let data = try await pickerItem.loadTransferable(type: Data.self),
                      let image = await ProfilePhotoRenderer.previewImage(from: data) else {
                    await MainActor.run {
                        showDeniedAlert = true
                        isLoadingPhoto = false
                    }
                    return
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    selectedImage = image
                    showCropper = true
                    self.pickerItem = nil
                    isLoadingPhoto = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.pickerItem = nil
                    showDeniedAlert = true
                    isLoadingPhoto = false
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

// MARK: - Profile Setup Screen

private struct ProfileSetupScreen: View {
    @Binding var username: String
    @Binding var homeCountry: String
    @Binding var profilePhotoData: Data
    let onContinue: () -> Void

    @State private var suggestions: [Country] = []
    @State private var didAttemptContinue = false
    @FocusState private var focusedField: ProfileField?
    @Environment(\.colorScheme) private var colorScheme

    private enum ProfileField {
        case name, country
    }

    private var canContinue: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isCountryValid
    }

    private var cleanCountry: String {
        homeCountry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedCountry: Country? {
        GeoJSONLoader.shared.country(withISOCode: cleanCountry) ??
            GeoJSONLoader.shared.country(named: cleanCountry)
    }

    private var countryEntryText: Binding<String> {
        Binding(
            get: {
                selectedCountry?.displayName ?? homeCountry
            },
            set: { newValue in
                homeCountry = newValue
            }
        )
    }

    private var isCountryValid: Bool {
        guard let country = selectedCountry else {
            return false
        }
        return country.isoCode == cleanCountry.uppercased() ||
            country.displayName.localizedCaseInsensitiveCompare(cleanCountry) == .orderedSame
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    headerSection
                    fieldsSection
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 34)
                .padding(.bottom, 128)
            }
            .onChange(of: focusedField) { _, field in
                guard let field else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(field, anchor: .center)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
        .safeAreaInset(edge: .bottom) {
            footerButtons
                .background(.regularMaterial)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear { GeoJSONLoader.shared.loadIfNeeded() }
    }

    private var headerSection: some View {
        VStack(spacing: 0) {
            Text(WanderlustL10n.string("Set Up Your Profile", table: .account))
                .font(.title.bold())
        }
    }

    private var fieldsSection: some View {
        VStack(spacing: 18) {
            OnboardingProfilePhotoPicker(profilePhotoData: $profilePhotoData)
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text(WanderlustL10n.string("Username", table: .account, fallback: "Username"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(WanderlustL10n.string("Enter your username", table: .account, fallback: "Enter your username"), text: $username)
                    .textContentType(.nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .country
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(profileFieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(focusedField == .name ? Color.blue.opacity(0.42) : Color.primary.opacity(0.06), lineWidth: 1)
                    }

                if didAttemptContinue,
                   username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(WanderlustL10n.string("Name is required.", table: .errors))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .id(ProfileField.name)

            VStack(alignment: .leading, spacing: 8) {
                Text(WanderlustL10n.string("Home Country", table: .account))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(String(localized: "Japan, France, Germany…"), text: countryEntryText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .country)
                    .submitLabel(.done)
                    .onSubmit {
                        focusedField = nil
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(profileFieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(focusedField == .country ? Color.blue.opacity(0.42) : Color.primary.opacity(0.06), lineWidth: 1)
                    }
                    .onChange(of: homeCountry) { _, _ in updateSuggestions() }

                if didAttemptContinue,
                   homeCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(WanderlustL10n.string("Home Country is required.", table: .errors))
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if didAttemptContinue,
                          !isCountryValid {
                    Text(WanderlustL10n.string("Select a country from the list.", table: .errors))
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if !suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(suggestions) { country in
                            Button {
                                homeCountry = country.isoCode
                                suggestions = []
                                focusedField = nil
                            } label: {
                                HStack(spacing: 12) {
                                    Text(country.flagEmoji).font(.title3)
                                    Text(country.displayName).foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                            if country.id != suggestions.last?.id {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                    .background(profileFieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                }
            }
            .id(ProfileField.country)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05), lineWidth: 1)
        }
    }

    private var profileFieldBackground: Color {
        colorScheme == .dark ? Color(.tertiarySystemBackground) : Color(.systemBackground)
    }

    private var footerButtons: some View {
        VStack(spacing: 12) {
            Button {
                didAttemptContinue = true
                guard canContinue else { return }
                focusedField = nil
                if let country = selectedCountry {
                    homeCountry = country.isoCode
                }
                onContinue()
            } label: {
                Text(String(localized: "Continue"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(canContinue ? Color.blue : Color.secondary.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(!canContinue)
            .padding(.horizontal, 32)
        }
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private func updateSuggestions() {
        let q = homeCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { suggestions = []; return }
        if let exact = GeoJSONLoader.shared.country(named: q),
           exact.name.localizedCaseInsensitiveCompare(q) == .orderedSame {
            suggestions = []
            return
        }
        suggestions = GeoJSONLoader.shared.searchCountries(query: q, limit: 5)
    }
}

// MARK: - Location Permission Screen

private struct LocationPermissionScreen: View {
    let onComplete: () -> Void

    @StateObject private var locationHelper = LocationRequestHelper()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.10))
                        .frame(width: 140, height: 140)

                    Image(systemName: "location.fill")
                        .wanderlustDecorativeFont(60)
                        .foregroundStyle(Color.blue)
                }

                VStack(spacing: 12) {
                    Text(WanderlustL10n.string("Enable Location", table: .settings))
                        .font(.title.bold())

                    Text(WanderlustL10n.string("Wanderlust uses your location to show your current position.\nYou can use Wanderlust without location access.", table: .settings))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 330)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            VStack(spacing: 16) {
                Button {
                    locationHelper.onAuthorized = { onComplete() }
                    locationHelper.request(fallback: onComplete)
                } label: {
                    Text(WanderlustL10n.string("Allow Location", table: .settings))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 32)

                Button(action: onComplete) {
                    Text(String(localized: "Not Now"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }
            }
            .padding(.bottom, 52)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

// MARK: - Location Request Helper

private final class LocationRequestHelper: ObservableObject {
    private class Delegate: NSObject, CLLocationManagerDelegate {
        weak var parent: LocationRequestHelper?

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            guard manager.authorizationStatus != .notDetermined else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent?.onAuthorized?()
                self?.parent?.onAuthorized = nil
            }
        }
    }

    private let manager = CLLocationManager()
    private let delegate = Delegate()
    var onAuthorized: (() -> Void)?

    init() {
        delegate.parent = self
        manager.delegate = delegate
    }

    func request(fallback: @escaping () -> Void) {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            fallback()
        }
    }
}
