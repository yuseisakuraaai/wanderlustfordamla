import Foundation
import Combine
import UIKit
import AuthenticationServices
import CryptoKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif

struct WanderlustUser: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var email: String
    var homeCountryISO2: String?
    var profilePhotoData: Data?
    var profilePhotoURL: String?
    var profilePhotoUpdatedAt: Date?
    var isLocalOnly: Bool
    var isEmailVerified: Bool
    var accountType: String
    var creationDate: Date?
    var lastSignInDate: Date?
    var profileCompleted: Bool

    init(
        id: String,
        name: String,
        email: String,
        homeCountryISO2: String? = nil,
        profilePhotoData: Data? = nil,
        profilePhotoURL: String? = nil,
        profilePhotoUpdatedAt: Date? = nil,
        isLocalOnly: Bool,
        isEmailVerified: Bool = false,
        accountType: String? = nil,
        creationDate: Date? = nil,
        lastSignInDate: Date? = nil,
        profileCompleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.homeCountryISO2 = homeCountryISO2
        self.profilePhotoData = profilePhotoData
        self.profilePhotoURL = profilePhotoURL
        self.profilePhotoUpdatedAt = profilePhotoUpdatedAt
        self.isLocalOnly = isLocalOnly
        self.isEmailVerified = isEmailVerified
        self.accountType = accountType ?? (isLocalOnly ? "local" : "firebase")
        self.creationDate = creationDate
        self.lastSignInDate = lastSignInDate
        self.profileCompleted = profileCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, email, homeCountryISO2, profilePhotoData, profilePhotoURL, profilePhotoUpdatedAt, isLocalOnly, isEmailVerified, accountType, creationDate, lastSignInDate, profileCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        homeCountryISO2 = try container.decodeIfPresent(String.self, forKey: .homeCountryISO2)
        profilePhotoData = try container.decodeIfPresent(Data.self, forKey: .profilePhotoData)
        profilePhotoURL = try container.decodeIfPresent(String.self, forKey: .profilePhotoURL)
        profilePhotoUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .profilePhotoUpdatedAt)
        isLocalOnly = try container.decodeIfPresent(Bool.self, forKey: .isLocalOnly) ?? true
        isEmailVerified = try container.decodeIfPresent(Bool.self, forKey: .isEmailVerified) ?? false
        accountType = try container.decodeIfPresent(String.self, forKey: .accountType) ?? (isLocalOnly ? "local" : "firebase")
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
        lastSignInDate = try container.decodeIfPresent(Date.self, forKey: .lastSignInDate)
        profileCompleted = try container.decodeIfPresent(Bool.self, forKey: .profileCompleted) ??
            (!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && homeCountryISO2?.isEmpty == false)
    }
}

enum AuthenticationState: Equatable {
    case checking
    case signedOut
    case signedIn
}

enum WanderlustPasswordPolicy {
    static let minimumLength = 8

    static func isValid(_ password: String) -> Bool {
        password.count >= minimumLength &&
            password.rangeOfCharacter(from: .uppercaseLetters) != nil &&
            password.rangeOfCharacter(from: .lowercaseLetters) != nil &&
            password.rangeOfCharacter(from: .decimalDigits) != nil
    }

    static var requirementMessage: String {
        WanderlustL10n.string(
            "Password must be at least 8 characters and include uppercase, lowercase, and a number.",
            table: .errors,
            fallback: "Password must be at least 8 characters and include uppercase, lowercase, and a number."
        )
    }
}

#if canImport(FirebaseAuth)
protocol AuthenticationServiceProtocol {
    var firebaseCurrentUser: FirebaseAuth.User? { get }

    func createAccount(email: String, password: String) async throws -> FirebaseAuth.User
    func signIn(email: String, password: String) async throws -> FirebaseAuth.User
    func sendPasswordReset(email: String) async throws
    func signOut() throws
    func deleteCurrentUser() async throws
    func sendEmailVerification() async throws
}
#endif

protocol AuthenticationService {
    var currentUser: WanderlustUser? { get }

    func createAccount(
        name: String,
        email: String,
        password: String,
        homeCountryISO2: String?,
        profilePhotoData: Data?
    ) async throws -> WanderlustUser

    func signIn(email: String, password: String) async throws -> WanderlustUser
    func signInWithGoogle() async throws -> WanderlustUser
    func signInWithApple() async throws -> WanderlustUser

    func signOut() async throws
    func deleteAccount() async throws
    func reauthenticateAndDelete(credential: ReauthCredential) async throws
    func resetPassword(email: String) async throws
    func sendEmailVerification() async throws
    func changePassword(currentPassword: String, newPassword: String) async throws
    func changeEmail(newEmail: String, currentPassword: String) async throws
    func reloadCurrentUser() async throws -> WanderlustUser?
    func updateProfile(name: String, homeCountryISO2: String?, profilePhotoData: Data?) async throws -> WanderlustUser
    func syncSettings(appearance: String, homeCountryHighlight: Bool, homeCountryISO2: String?) async throws
    func migrateLocalDataToCurrentAccount() async throws
}

@MainActor
protocol AuthenticationStateListening: AnyObject {
    func startAuthStateListener(_ handler: @escaping (WanderlustUser?) -> Void)
    func stopAuthStateListener()
}

enum ReauthCredential {
    case email(String, String)
    case google
    case apple
}

enum AuthenticationError: LocalizedError {
    case backendUnavailable
    case invalidCredentials
    case passwordResetUnavailable
    case googleSignInUnavailable
    case googleSignInCancelled
    case appleSignInUnavailable
    case appleSignInCancelled
    case firebaseNotConfigured
    case profileSaveFailed
    case reauthenticationRequired
    case passwordDoesNotMeetRequirements
    case duplicateEmailDifferentProvider

    var errorDescription: String? {
        switch self {
        case .backendUnavailable:
            WanderlustL10n.string("Online accounts are not configured yet. Wanderlust will save this profile only on this device.", table: .errors)
        case .invalidCredentials:
            WanderlustL10n.string("The email or password is incorrect.", table: .errors)
        case .passwordResetUnavailable:
            WanderlustL10n.string("Password reset requires an online authentication backend and is not available for local profiles.", table: .errors)
        case .googleSignInUnavailable:
            WanderlustL10n.string("Google Sign-In is not available right now. Please try another sign-in method.", table: .errors)
        case .googleSignInCancelled:
            WanderlustL10n.string("Google Sign-In was canceled.", table: .errors)
        case .appleSignInUnavailable:
            WanderlustL10n.string("Sign in with Apple is not available right now. Please try another sign-in method.", table: .errors, fallback: "Sign in with Apple is not available right now. Please try another sign-in method.")
        case .appleSignInCancelled:
            WanderlustL10n.string("Sign in with Apple was canceled.", table: .errors, fallback: "Sign in with Apple was canceled.")
        case .firebaseNotConfigured:
            WanderlustL10n.string("Online accounts are not available right now. Please try again later.", table: .errors)
        case .profileSaveFailed:
            WanderlustL10n.string("The account was created, but the profile could not be saved. Please try again.", table: .errors)
        case .reauthenticationRequired:
            WanderlustL10n.string("For security, sign in again before deleting this account.", table: .errors)
        case .passwordDoesNotMeetRequirements:
            WanderlustPasswordPolicy.requirementMessage
        case .duplicateEmailDifferentProvider:
            WanderlustL10n.string(
                "This email address is already registered with a different sign-in method. Please use the method you first registered with.",
                table: .errors,
                fallback: "This email address is already registered with a different sign-in method. Please use the method you first registered with."
            )
        }
    }
}

enum FirebaseErrorMapper {
    static func message(for error: Error) -> String {
        #if DEBUG
        let nsError = error as NSError
        WanderlustDiagnostics.warning(
            "firebase error domain=\(nsError.domain) code=\(nsError.code)",
            category: .auth
        )
        #endif

        #if canImport(FirebaseAuth)
        let authError = error as NSError
        if authError.domain == AuthErrorDomain,
           let code = AuthErrorCode(rawValue: authError.code) {
            switch code {
            case .networkError:
                return WanderlustL10n.string("Network connection failed. Check your connection and try again.", table: .errors)
            case .invalidEmail:
                return WanderlustL10n.string("Enter a valid email address.", table: .errors)
            case .weakPassword:
                return WanderlustPasswordPolicy.requirementMessage
            case .emailAlreadyInUse:
                return WanderlustL10n.string("This email address is already in use.", table: .errors)
            case .userNotFound, .wrongPassword, .invalidCredential:
                return WanderlustL10n.string("The email or password is incorrect.", table: .errors)
            case .tooManyRequests:
                return WanderlustL10n.string("Too many attempts. Please wait and try again.", table: .errors)
            case .requiresRecentLogin:
                return WanderlustL10n.string("For security, sign in again before continuing.", table: .errors)
            case .operationNotAllowed:
                return WanderlustL10n.string("This sign-in method is not available right now.", table: .errors)
            case .accountExistsWithDifferentCredential:
                return WanderlustL10n.string(
                    "This email address is already registered with a different sign-in method. Please use the method you first registered with.",
                    table: .errors,
                    fallback: "This email address is already registered with a different sign-in method. Please use the method you first registered with."
                )
            default:
                break
            }
        }
        #endif

        #if canImport(FirebaseFirestore)
        if let firestoreError = error as? FirestoreErrorCode {
            switch firestoreError.code {
            case .permissionDenied:
                return WanderlustL10n.string("You do not have permission to access this data.", table: .errors)
            case .unavailable:
                return WanderlustL10n.string("Account services are temporarily unavailable. Try again later.", table: .errors)
            default:
                break
            }
        }
        #endif

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return WanderlustL10n.string("Something went wrong. Please try again.", table: .errors)
    }
}

@MainActor
final class AuthenticationStore: ObservableObject {
    static let shared = AuthenticationStore(service: AuthenticationServiceFactory.makeService())

    @Published private(set) var currentUser: WanderlustUser?
    @Published private(set) var authenticationState: AuthenticationState = .checking
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var requiresReauthForDeletion = false

    private let service: AuthenticationService
    private var listener: AuthenticationStateListening?

    init(service: AuthenticationService) {
        self.service = service

        if let listener = service as? AuthenticationStateListening {
            self.listener = listener
            currentUser = nil
            authenticationState = .checking
            listener.startAuthStateListener { [weak self] user in
                guard let self else { return }
                currentUser = user
                if let user {
                    Self.persistDisplayCache(for: user)
                    authenticationState = .signedIn
                    if user.isLocalOnly {
                        TripStore.shared.deactivateCloudSync()
                    } else {
                        TripStore.shared.activateCloudSync(for: user.id)
                    }
                } else {
                    authenticationState = .signedOut
                    TripStore.shared.deactivateCloudSync()
                }
            }
        } else {
            currentUser = service.currentUser
            authenticationState = currentUser == nil ? .signedOut : .signedIn
        }
    }

    deinit {
        Task { @MainActor [listener] in
            listener?.stopAuthStateListener()
        }
    }

    var authenticationError: String? {
        get { errorMessage }
        set { errorMessage = newValue }
    }

    var isProcessing: Bool { isLoading }
    var isSignedIn: Bool { currentUser != nil && authenticationState == .signedIn }
    var isEmailVerified: Bool { currentUser?.isEmailVerified ?? false }
    var isLocalOnly: Bool { currentUser?.isLocalOnly ?? true }

    func createAccount(
        name: String,
        email: String,
        password: String,
        homeCountryISO2: String?,
        profilePhotoData: Data?
    ) async -> WanderlustUser? {
        await perform {
            try await service.createAccount(
                name: name,
                email: email,
                password: password,
                homeCountryISO2: homeCountryISO2,
                profilePhotoData: profilePhotoData
            )
        }
    }

    func signIn(email: String, password: String) async -> WanderlustUser? {
        await perform { try await service.signIn(email: email, password: password) }
    }

    func signInWithGoogle() async -> WanderlustUser? {
        await perform { try await service.signInWithGoogle() }
    }

    func signInWithApple() async -> WanderlustUser? {
        await perform { try await service.signInWithApple() }
    }

    func signOut() async -> Bool {
        await performVoid { try await service.signOut() }
    }

    func deleteAccount() async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        errorMessage = nil
        requiresReauthForDeletion = false
        defer { isLoading = false }
        do {
            try await service.deleteAccount()
            currentUser = service.currentUser
            authenticationState = .signedOut
            TripStore.shared.deactivateCloudSync()
            return true
        } catch AuthenticationError.reauthenticationRequired {
            requiresReauthForDeletion = true
            return false
        } catch {
            errorMessage = FirebaseErrorMapper.message(for: error)
            return false
        }
    }

    func reauthenticateAndDelete(credential: ReauthCredential) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await service.reauthenticateAndDelete(credential: credential)
            requiresReauthForDeletion = false
            currentUser = service.currentUser
            authenticationState = .signedOut
            TripStore.shared.deactivateCloudSync()
            return true
        } catch {
            errorMessage = FirebaseErrorMapper.message(for: error)
            return false
        }
    }

    func cancelReauthForDeletion() {
        requiresReauthForDeletion = false
    }

    func resetPassword(email: String) async -> Bool {
        await performVoid { try await service.resetPassword(email: email) }
    }

    func sendEmailVerification() async -> Bool {
        await performVoid { try await service.sendEmailVerification() }
    }

    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        await performVoid {
            try await service.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
        }
    }

    func changeEmail(newEmail: String, currentPassword: String) async -> Bool {
        await performVoid {
            try await service.changeEmail(
                newEmail: newEmail,
                currentPassword: currentPassword
            )
        }
    }

    func reloadCurrentUser() async -> WanderlustUser? {
        guard !isLoading else { return currentUser }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let user = try await service.reloadCurrentUser()
            currentUser = user
            if let user {
                Self.persistDisplayCache(for: user)
            }
            authenticationState = user == nil ? .signedOut : .signedIn
            return user
        } catch {
            errorMessage = FirebaseErrorMapper.message(for: error)
            return currentUser
        }
    }

    func updateProfile(name: String, homeCountryISO2: String?, profilePhotoData: Data?) async -> WanderlustUser? {
        await perform {
            try await service.updateProfile(
                name: name,
                homeCountryISO2: homeCountryISO2,
                profilePhotoData: profilePhotoData
            )
        }
    }

    func syncSettings(appearance: String, homeCountryHighlight: Bool, homeCountryISO2: String?) {
        guard authenticationState == .signedIn else { return }
        Task {
            try? await service.syncSettings(
                appearance: appearance,
                homeCountryHighlight: homeCountryHighlight,
                homeCountryISO2: homeCountryISO2
            )
        }
    }

    func migrateLocalDataToCurrentAccount() async -> Bool {
        await performVoid {
            try await service.migrateLocalDataToCurrentAccount()
        }
    }

    private func perform(_ operation: () async throws -> WanderlustUser) async -> WanderlustUser? {
        guard !isLoading else { return nil }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let user = try await operation()
            currentUser = user
            Self.persistDisplayCache(for: user)
            authenticationState = .signedIn
            if user.isLocalOnly {
                TripStore.shared.deactivateCloudSync()
            } else {
                TripStore.shared.activateCloudSync(for: user.id)
            }
            return user
        } catch {
            errorMessage = FirebaseErrorMapper.message(for: error)
            return nil
        }
    }

    @discardableResult
    private func performVoid(_ operation: () async throws -> Void) async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await operation()
            currentUser = service.currentUser
            if let currentUser {
                Self.persistDisplayCache(for: currentUser)
            }
            authenticationState = currentUser == nil ? .signedOut : .signedIn
            if let currentUser, !currentUser.isLocalOnly {
                TripStore.shared.activateCloudSync(for: currentUser.id)
            } else {
                TripStore.shared.deactivateCloudSync()
            }
            return true
        } catch {
            errorMessage = FirebaseErrorMapper.message(for: error)
            return false
        }
    }

    private static func persistDisplayCache(for user: WanderlustUser) {
        UserDefaults.standard.set(user.name, forKey: "atlas.username")
        UserDefaults.standard.set(user.email, forKey: "atlas.email")
        if let homeCountryISO2 = user.homeCountryISO2 {
            UserDefaults.standard.set(homeCountryISO2, forKey: "atlas.homeCountry")
        }
        if let profilePhotoData = user.profilePhotoData, !profilePhotoData.isEmpty {
            UserDefaults.standard.set(profilePhotoData, forKey: "atlas.profilePhotoData")
        } else if user.profilePhotoURL == nil {
            UserDefaults.standard.removeObject(forKey: "atlas.profilePhotoData")
        }
    }
}

private enum AuthenticationServiceFactory {
    @MainActor
    static func makeService() -> AuthenticationService {
        #if canImport(FirebaseAuth)
        if Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil {
            return FirebaseAuthenticationService()
        }
        #endif
        return LocalAuthenticationService()
    }
}

#if canImport(FirebaseAuth)
@MainActor
final class FirebaseAuthenticationService: AuthenticationService, AuthenticationServiceProtocol, AuthenticationStateListening {
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    var currentUser: WanderlustUser? { wanderlustCurrentUser }
    var firebaseCurrentUser: FirebaseAuth.User? { Auth.auth().currentUser }

    private var wanderlustCurrentUser: WanderlustUser? {
        guard let user = Auth.auth().currentUser else { return nil }
        return Self.wanderlustUser(from: user)
    }
}
#endif

#if canImport(FirebaseAuth)
extension FirebaseAuthenticationService {
    func startAuthStateListener(_ handler: @escaping (WanderlustUser?) -> Void) {
        guard authStateHandle == nil else { return }
        authStateHandle = Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor in
                if let user {
                    WanderlustDiagnostics.info("initial profile fetch started", category: .sync)
                    do {
                        let resolvedUser = try await self.loadWanderlustUser(for: user)
                        WanderlustDiagnostics.info("initial profile fetch completed", category: .sync)
                        handler(resolvedUser)
                    } catch {
                        WanderlustDiagnostics.error(error, category: .sync, message: "initial profile fetch failed")
                        handler(nil)
                    }
                } else {
                    handler(nil)
                }
            }
        }
    }

    func stopAuthStateListener() {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
            self.authStateHandle = nil
        }
    }

    func createAccount(email: String, password: String) async throws -> FirebaseAuth.User {
        try await Auth.auth().createUser(withEmail: email, password: password).user
    }

    func signIn(email: String, password: String) async throws -> FirebaseAuth.User {
        try await Auth.auth().signIn(withEmail: email, password: password).user
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func deleteCurrentUser() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.delete()
    }

    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else { throw AuthenticationError.invalidCredentials }
        try await user.sendEmailVerification()
    }

    func createAccount(
        name: String,
        email: String,
        password: String,
        homeCountryISO2: String?,
        profilePhotoData: Data?
    ) async throws -> WanderlustUser {
        guard FirebaseAppGuard.isConfigured else { throw AuthenticationError.firebaseNotConfigured }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else {
            throw AuthenticationError.invalidCredentials
        }
        guard WanderlustPasswordPolicy.isValid(password) else {
            throw AuthenticationError.passwordDoesNotMeetRequirements
        }

        let authUser: FirebaseAuth.User
        do {
            authUser = try await createAccount(email: trimmedEmail, password: password)
        } catch let nsError as NSError
            where AuthErrorCode(rawValue: nsError.code) == .emailAlreadyInUse {
            throw AuthenticationError.duplicateEmailDifferentProvider
        }
        do {
            let changeRequest = authUser.createProfileChangeRequest()
            if !trimmedName.isEmpty {
                changeRequest.displayName = trimmedName
                try await changeRequest.commitChanges()
            }

            let uploadedPhoto = try await uploadProfilePhotoIfNeeded(profilePhotoData, uid: authUser.uid)
            try await saveUserProfile(
                uid: authUser.uid,
                name: trimmedName,
                email: authUser.email ?? trimmedEmail,
                homeCountryISO2: homeCountryISO2,
                profilePhotoURL: uploadedPhoto?.url,
                profilePhotoUpdatedAt: uploadedPhoto?.updatedAt,
                profilePhotoData: uploadedPhoto?.data ?? profilePhotoData,
                accountType: "email",
                profileCompleted: Self.isProfileComplete(
                    name: trimmedName,
                    homeCountryISO2: homeCountryISO2,
                    profilePhotoURL: uploadedPhoto?.url,
                    profilePhotoData: uploadedPhoto?.data
                )
            )
            try? await authUser.sendEmailVerification()

            return WanderlustUser(
                id: authUser.uid,
                name: trimmedName,
                email: authUser.email ?? trimmedEmail,
                homeCountryISO2: homeCountryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                profilePhotoData: uploadedPhoto?.data,
                profilePhotoURL: uploadedPhoto?.url,
                profilePhotoUpdatedAt: uploadedPhoto?.updatedAt,
                isLocalOnly: false,
                isEmailVerified: authUser.isEmailVerified,
                accountType: "email",
                creationDate: authUser.metadata.creationDate,
                lastSignInDate: authUser.metadata.lastSignInDate,
                profileCompleted: Self.isProfileComplete(
                    name: trimmedName,
                    homeCountryISO2: homeCountryISO2,
                    profilePhotoURL: uploadedPhoto?.url,
                    profilePhotoData: uploadedPhoto?.data
                )
            )
        } catch {
            try? await authUser.delete()
            throw error
        }
    }

    func signIn(email: String, password: String) async throws -> WanderlustUser {
        guard FirebaseAppGuard.isConfigured else { throw AuthenticationError.firebaseNotConfigured }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), !password.isEmpty else {
            throw AuthenticationError.invalidCredentials
        }

        let authUser = try await Auth.auth().signIn(withEmail: trimmedEmail, password: password).user
        return try await loadWanderlustUser(for: authUser)
    }

    func signInWithGoogle() async throws -> WanderlustUser {
        guard FirebaseAppGuard.isConfigured else { throw AuthenticationError.firebaseNotConfigured }
        #if canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthenticationError.firebaseNotConfigured
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presentingViewController = UIApplication.shared.wanderlustTopViewController() else {
            throw AuthenticationError.googleSignInUnavailable
        }
        let googleResult: GIDSignInResult
        do {
            googleResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        } catch {
            let nsError = error as NSError
            if nsError.domain == kGIDSignInErrorDomain {
                throw AuthenticationError.googleSignInCancelled
            }
            throw error
        }
        guard let idToken = googleResult.user.idToken?.tokenString else {
            throw AuthenticationError.invalidCredentials
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: googleResult.user.accessToken.tokenString
        )
        let result: AuthDataResult
        do {
            result = try await Auth.auth().signIn(with: credential)
        } catch let nsError as NSError
            where AuthErrorCode(rawValue: nsError.code) == .accountExistsWithDifferentCredential {
            throw Self.duplicateAccountError()
        }
        let fallbackName = result.user.displayName ?? googleResult.user.profile?.name ?? ""
        let fallbackEmail = result.user.email ?? googleResult.user.profile?.email ?? ""
        let existing = try? await loadProfileDocument(uid: result.user.uid)
        if existing == nil {
            try await saveUserProfile(
                uid: result.user.uid,
                name: fallbackName,
                email: fallbackEmail,
                homeCountryISO2: nil,
                profilePhotoURL: nil,
                accountType: "google"
            )
        }
        return try await loadWanderlustUser(for: result.user, fallbackName: fallbackName, fallbackEmail: fallbackEmail)
        #else
        throw AuthenticationError.googleSignInUnavailable
    #endif
    }

    func signOut() async throws {
        try Auth.auth().signOut()
    }

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        do {
            try await deleteCloudProfile(uid: user.uid)
            try await user.delete()
        } catch let nsError as NSError
            where AuthErrorCode(rawValue: nsError.code) == .requiresRecentLogin {
            throw AuthenticationError.reauthenticationRequired
        }
    }

    func reauthenticateAndDelete(credential: ReauthCredential) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthenticationError.invalidCredentials
        }
        switch credential {
        case .email(let email, let password):
            let authCredential = EmailAuthProvider.credential(withEmail: email, password: password)
            try await user.reauthenticate(with: authCredential)
        case .google:
            #if canImport(GoogleSignIn)
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw AuthenticationError.googleSignInUnavailable
            }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            guard let vc = UIApplication.shared.wanderlustTopViewController() else {
                throw AuthenticationError.googleSignInUnavailable
            }
            let googleResult: GIDSignInResult
            do {
                googleResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: vc)
            } catch {
                let nsError = error as NSError
                if nsError.domain == kGIDSignInErrorDomain {
                    throw AuthenticationError.googleSignInCancelled
                }
                throw error
            }
            guard let idToken = googleResult.user.idToken?.tokenString else {
                throw AuthenticationError.invalidCredentials
            }
            let googleCredential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: googleResult.user.accessToken.tokenString
            )
            try await user.reauthenticate(with: googleCredential)
            #else
            throw AuthenticationError.googleSignInUnavailable
            #endif
        case .apple:
            let nonce = randomNonceString()
            let hashedNonce = sha256(nonce)
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })?
                .windows.first(where: { $0.isKeyWindow }) else {
                throw AuthenticationError.appleSignInUnavailable
            }
            let authorization = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ASAuthorization, Error>) in
                let coordinator = AppleSignInCoordinator(continuation: cont, window: window)
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = coordinator
                controller.presentationContextProvider = coordinator
                objc_setAssociatedObject(controller, &AppleSignInCoordinator.retainKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                controller.performRequests()
            }
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = appleCredential.identityToken,
                  let tokenString = String(data: tokenData, encoding: .utf8) else {
                throw AuthenticationError.invalidCredentials
            }
            let appleFirebaseCredential = OAuthProvider.appleCredential(
                withIDToken: tokenString,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )
            try await user.reauthenticate(with: appleFirebaseCredential)
        }
        let uid = user.uid
        try await deleteCloudProfile(uid: uid)
        try await user.delete()
    }

    func resetPassword(email: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else { throw AuthenticationError.invalidCredentials }
        try await sendPasswordReset(email: trimmedEmail)
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard let user = Auth.auth().currentUser,
              let email = user.email,
              !currentPassword.isEmpty else {
            throw AuthenticationError.invalidCredentials
        }
        guard WanderlustPasswordPolicy.isValid(newPassword) else {
            throw AuthenticationError.passwordDoesNotMeetRequirements
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
        try await user.reauthenticate(with: credential)
        try await user.updatePassword(to: newPassword)
    }

    func changeEmail(newEmail: String, currentPassword: String) async throws {
        guard let user = Auth.auth().currentUser,
              let currentEmail = user.email,
              newEmail.trimmingCharacters(in: .whitespacesAndNewlines).contains("@"),
              !currentPassword.isEmpty else {
            throw AuthenticationError.invalidCredentials
        }
        let cleanedEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential = EmailAuthProvider.credential(withEmail: currentEmail, password: currentPassword)
        try await user.reauthenticate(with: credential)
        try await user.sendEmailVerification(beforeUpdatingEmail: cleanedEmail)
    }

    func reloadCurrentUser() async throws -> WanderlustUser? {
        guard let user = Auth.auth().currentUser else { return nil }
        try await user.reload()
        guard let reloadedUser = Auth.auth().currentUser else { return nil }
        let currentUser = try await loadWanderlustUser(for: reloadedUser)
        if let email = reloadedUser.email, !email.isEmpty {
            try? await saveUserProfile(
                uid: reloadedUser.uid,
                name: currentUser.name,
                email: email,
                homeCountryISO2: currentUser.homeCountryISO2,
                profilePhotoURL: currentUser.profilePhotoURL,
                profilePhotoUpdatedAt: currentUser.profilePhotoUpdatedAt,
                profilePhotoData: currentUser.profilePhotoData,
                accountType: currentUser.accountType,
                profileCompleted: currentUser.profileCompleted
            )
        }
        return currentUser
    }

    func updateProfile(name: String, homeCountryISO2: String?, profilePhotoData: Data?) async throws -> WanderlustUser {
        guard let user = Auth.auth().currentUser else {
            throw AuthenticationError.invalidCredentials
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AuthenticationError.invalidCredentials
        }
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = trimmedName
        try await changeRequest.commitChanges()
        if profilePhotoData == nil {
            try? await ProfilePhotoLocalStore.delete(uid: user.uid)
            try? await deleteProfilePhotoFromStorage(uid: user.uid)
        }
        let uploadedPhoto = try await uploadProfilePhotoIfNeeded(profilePhotoData, uid: user.uid)
        let existingProfile = try? await loadProfileDocument(uid: user.uid)
        let cachedPhotoData: Data?
        if profilePhotoData == nil {
            cachedPhotoData = nil
        } else if let uploadedData = uploadedPhoto?.data {
            cachedPhotoData = uploadedData
        } else {
            cachedPhotoData = await resolvedLocalProfilePhotoData(
                uid: user.uid,
                profilePhotoURL: existingProfile?.profilePhotoURL,
                embeddedProfilePhotoData: existingProfile?.profilePhotoData,
                remoteUpdatedAt: existingProfile?.profilePhotoUpdatedAt
            )
        }
        let resolvedPhotoURL = profilePhotoData == nil ? nil : uploadedPhoto?.url ?? existingProfile?.profilePhotoURL
        let resolvedPhotoUpdatedAt = profilePhotoData == nil ? nil : uploadedPhoto?.updatedAt ?? existingProfile?.profilePhotoUpdatedAt
        let completed = Self.isProfileComplete(
            name: trimmedName,
            homeCountryISO2: homeCountryISO2,
            profilePhotoURL: resolvedPhotoURL,
            profilePhotoData: cachedPhotoData
        )
        let accountType: String
        switch user.providerData.first?.providerID {
        case "google.com":
            accountType = "google"
        case "apple.com":
            accountType = "apple"
        default:
            accountType = "email"
        }
        try await saveUserProfile(
            uid: user.uid,
            name: trimmedName,
            email: user.email ?? "",
            homeCountryISO2: homeCountryISO2,
            profilePhotoURL: resolvedPhotoURL,
            profilePhotoUpdatedAt: resolvedPhotoUpdatedAt,
            profilePhotoData: cachedPhotoData,
            accountType: accountType,
            profileCompleted: completed,
            deletesProfilePhoto: profilePhotoData == nil
        )
        return WanderlustUser(
            id: user.uid,
            name: trimmedName,
            email: user.email ?? "",
            homeCountryISO2: homeCountryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            profilePhotoData: cachedPhotoData,
            profilePhotoURL: resolvedPhotoURL,
            profilePhotoUpdatedAt: resolvedPhotoUpdatedAt,
            isLocalOnly: false,
            isEmailVerified: user.isEmailVerified,
            accountType: accountType,
            creationDate: user.metadata.creationDate,
            lastSignInDate: user.metadata.lastSignInDate,
            profileCompleted: completed
        )
    }

    func syncSettings(appearance: String, homeCountryHighlight: Bool, homeCountryISO2: String?) async throws {
        guard let user = Auth.auth().currentUser else { return }
        #if canImport(FirebaseFirestore)
        var data: [String: Any] = [
            "appearance": appearance,
            "homeCountryHighlight": homeCountryHighlight,
            "updatedAt": Timestamp(date: Date()),
            "schemaVersion": 1
        ]
        if let homeCountryISO2, !homeCountryISO2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["homeCountryISO2"] = homeCountryISO2.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        try await Firestore.firestore()
            .collection("users")
            .document(user.uid)
            .collection("settings")
            .document("app")
            .setData(data, merge: true)
        #endif
    }

    func migrateLocalDataToCurrentAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthenticationError.invalidCredentials
        }
        let existingProfile = try? await loadProfileDocument(uid: user.uid)
        let resolvedName: String
        if let existingName = existingProfile?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !existingName.isEmpty {
            resolvedName = existingProfile?.name ?? existingName
        } else {
            resolvedName = user.displayName ?? ""
        }
        let resolvedEmail: String
        if let existingEmail = existingProfile?.email.trimmingCharacters(in: .whitespacesAndNewlines),
           !existingEmail.isEmpty {
            resolvedEmail = existingProfile?.email ?? existingEmail
        } else {
            resolvedEmail = user.email ?? ""
        }
        let accountType = existingProfile?.accountType ?? (user.providerData.first?.providerID == "google.com" ? "google" : "email")
        try await saveUserProfile(
            uid: user.uid,
            name: resolvedName,
            email: resolvedEmail,
            homeCountryISO2: existingProfile?.homeCountryISO2,
            profilePhotoURL: existingProfile?.profilePhotoURL,
            profilePhotoUpdatedAt: existingProfile?.profilePhotoUpdatedAt,
            profilePhotoData: existingProfile?.profilePhotoData,
            accountType: accountType,
            profileCompleted: existingProfile?.profileCompleted ?? false
        )
        try await uploadLocalTripsForMigration(uid: user.uid)
        _ = TripStore.shared.save()
    }

    private func uploadLocalTripsForMigration(uid: String) async throws {
        #if canImport(FirebaseFirestore)
        let trips = TripStore.shared.trips
        guard !trips.isEmpty else { return }

        let encodedTrips = try await MainActor.run {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try trips.map { trip -> (Trip, [String: Any]) in
                let data = try encoder.encode(trip)
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                guard var dictionary = object as? [String: Any] else {
                    throw AuthenticationError.profileSaveFailed
                }
                dictionary["ownerUID"] = uid
                dictionary["schemaVersion"] = 1
                return (trip, dictionary)
            }
        }

        let db = Firestore.firestore()
        let batch = db.batch()
        let now = Timestamp(date: Date())
        for (trip, dictionary) in encodedTrips {
            var firestoreData = dictionary
            firestoreData["updatedAt"] = now
            let document = db
                .collection("users")
                .document(uid)
                .collection("trips")
                .document(trip.id.uuidString)
            batch.setData(firestoreData, forDocument: document, merge: true)
        }
        try await batch.commit()
        #endif
    }

    private func loadWanderlustUser(
        for user: FirebaseAuth.User,
        fallbackName: String? = nil,
        fallbackEmail: String? = nil
    ) async throws -> WanderlustUser {
        if let profile = try await loadProfileDocument(uid: user.uid) {
            let photoData = await resolvedLocalProfilePhotoData(
                uid: user.uid,
                profilePhotoURL: profile.profilePhotoURL,
                embeddedProfilePhotoData: profile.profilePhotoData,
                remoteUpdatedAt: profile.profilePhotoUpdatedAt
            )
            let completed = Self.isProfileComplete(
                name: profile.name.isEmpty ? (user.displayName ?? fallbackName ?? "") : profile.name,
                homeCountryISO2: profile.homeCountryISO2,
                profilePhotoURL: profile.profilePhotoURL,
                profilePhotoData: photoData
            )
            return WanderlustUser(
                id: user.uid,
                name: profile.name.isEmpty ? (user.displayName ?? fallbackName ?? "") : profile.name,
                email: user.email ?? fallbackEmail ?? profile.email,
                homeCountryISO2: profile.homeCountryISO2,
                profilePhotoData: photoData,
                profilePhotoURL: profile.profilePhotoURL,
                profilePhotoUpdatedAt: profile.profilePhotoUpdatedAt,
                isLocalOnly: false,
                isEmailVerified: user.isEmailVerified,
                accountType: profile.accountType,
                creationDate: user.metadata.creationDate,
                lastSignInDate: user.metadata.lastSignInDate,
                profileCompleted: completed
            )
        }

        var fallbackUser = Self.wanderlustUser(from: user, fallbackName: fallbackName, fallbackEmail: fallbackEmail)
        fallbackUser.profileCompleted = false
        return fallbackUser
    }

    private func saveUserProfile(
        uid: String,
        name: String,
        email: String,
        homeCountryISO2: String?,
        profilePhotoURL: String?,
        profilePhotoUpdatedAt: Date? = nil,
        profilePhotoData: Data? = nil,
        accountType: String,
        profileCompleted: Bool = false,
        deletesProfilePhoto: Bool = false
    ) async throws {
        #if canImport(FirebaseFirestore)
        let db = Firestore.firestore()
        let now = Timestamp(date: Date())
        var data: [String: Any] = [
            "uid": uid,
            "displayName": name,
            "name": name,
            "email": email,
            "updatedAt": now,
            "accountType": accountType,
            "profileCompleted": profileCompleted,
            "schemaVersion": 1
        ]
        if let homeCountryISO2 {
            data["homeCountryISO2"] = homeCountryISO2.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        if let profilePhotoURL {
            data["profilePhotoURL"] = profilePhotoURL
        }
        if let profilePhotoUpdatedAt {
            data["profilePhotoUpdatedAt"] = Timestamp(date: profilePhotoUpdatedAt)
        }
        if let profilePhotoData,
           !profilePhotoData.isEmpty,
           let preparedData = await ProfilePhotoImageProcessor.preparedJPEGData(from: profilePhotoData, maxDimension: 384) {
            data["profilePhotoData"] = preparedData.base64EncodedString()
            if profilePhotoUpdatedAt == nil {
                data["profilePhotoUpdatedAt"] = now
            }
        }
        let document = db.collection("users").document(uid)
        let existing = try? await document.getDocument()
        if existing?.exists == true {
            if deletesProfilePhoto {
                data["profilePhotoURL"] = FieldValue.delete()
                data["profilePhotoData"] = FieldValue.delete()
                data["profilePhotoUpdatedAt"] = FieldValue.delete()
            }
            try await document.setData(data, merge: true)
        } else {
            data["createdAt"] = now
            try await document.setData(data, merge: true)
        }
        #else
        throw AuthenticationError.profileSaveFailed
        #endif
    }

    private func loadProfileDocument(uid: String) async throws -> FirebaseProfileDocument? {
        #if canImport(FirebaseFirestore)
        let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
        guard let data = snapshot.data() else { return nil }
        return FirebaseProfileDocument(data: data)
        #else
        return nil
        #endif
    }

    private func deleteCloudProfile(uid: String) async throws {
        try? await ProfilePhotoLocalStore.delete(uid: uid)
        #if canImport(FirebaseFirestore)
        try await Firestore.firestore().collection("users").document(uid).delete()
        #endif
    }

    private func deleteProfilePhotoFromStorage(uid: String) async throws {
        #if canImport(FirebaseStorage)
        let reference = Storage.storage().reference().child("users/\(uid)/profile/profile.jpg")
        try await reference.delete()
        #endif
    }

    func signInWithApple() async throws -> WanderlustUser {
        guard FirebaseAppGuard.isConfigured else { throw AuthenticationError.firebaseNotConfigured }
        let nonce = randomNonceString()
        let hashedNonce = sha256(nonce)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow }) else {
            throw AuthenticationError.appleSignInUnavailable
        }
        let authorization = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ASAuthorization, Error>) in
            let coordinator = AppleSignInCoordinator(continuation: cont, window: window)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = coordinator
            controller.presentationContextProvider = coordinator
            objc_setAssociatedObject(controller, &AppleSignInCoordinator.retainKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            controller.performRequests()
        }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let tokenString = String(data: tokenData, encoding: .utf8) else {
            throw AuthenticationError.invalidCredentials
        }
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: tokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        let authResult: AuthDataResult
        do {
            authResult = try await Auth.auth().signIn(with: firebaseCredential)
        } catch let nsError as NSError
            where AuthErrorCode(rawValue: nsError.code) == .accountExistsWithDifferentCredential {
            throw Self.duplicateAccountError()
        }
        let displayName: String
        if let name = credential.fullName, name.givenName != nil || name.familyName != nil {
            displayName = PersonNameComponentsFormatter().string(from: name)
        } else {
            displayName = authResult.user.displayName ?? ""
        }
        let email = credential.email ?? authResult.user.email ?? ""
        let existing = try? await loadProfileDocument(uid: authResult.user.uid)
        if existing == nil {
            try await saveUserProfile(
                uid: authResult.user.uid,
                name: displayName,
                email: email,
                homeCountryISO2: nil,
                profilePhotoURL: nil,
                accountType: "apple"
            )
        }
        return try await loadWanderlustUser(for: authResult.user, fallbackName: displayName, fallbackEmail: email)
    }

    private static func duplicateAccountError() -> Error {
        let message = WanderlustL10n.string(
            "This email address is already registered with a different sign-in method. Please use the method you first registered with.",
            table: .errors,
            fallback: "This email address is already registered with a different sign-in method. Please use the method you first registered with."
        )
        return DuplicateSignInMethodError(message: message)
    }

    fileprivate static func isProfileComplete(
        name: String,
        homeCountryISO2: String?,
        profilePhotoURL: String?,
        profilePhotoData: Data?
    ) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            homeCountryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            ((profilePhotoURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ||
             (profilePhotoData?.isEmpty == false))
    }

    private func resolvedLocalProfilePhotoData(
        uid: String,
        profilePhotoURL: String?,
        embeddedProfilePhotoData: Data?,
        remoteUpdatedAt: Date?
    ) async -> Data? {
        let localData = await ProfilePhotoLocalStore.loadData(uid: uid)
        let localUpdatedAt = await ProfilePhotoLocalStore.updatedAt(uid: uid)
        let shouldDownload = localData == nil ||
            (remoteUpdatedAt != nil && (localUpdatedAt == nil || remoteUpdatedAt! > localUpdatedAt!))

        if shouldDownload, let embeddedProfilePhotoData, !embeddedProfilePhotoData.isEmpty {
            let cached = try? await ProfilePhotoLocalStore.save(
                embeddedProfilePhotoData,
                uid: uid,
                updatedAt: remoteUpdatedAt
            )
            return cached ?? embeddedProfilePhotoData
        }

        guard shouldDownload,
              let profilePhotoURL,
              let url = URL(string: profilePhotoURL) else {
            return localData
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let cached = try await ProfilePhotoLocalStore.save(data, uid: uid, updatedAt: remoteUpdatedAt)
            WanderlustDiagnostics.info("profile photo download completed", category: .sync)
            return cached
        } catch {
            let nsError = error as NSError
            WanderlustDiagnostics.warning(
                "profile photo download failed domain=\(nsError.domain) code=\(nsError.code)",
                category: .sync
            )
            return localData
        }
    }

    private func uploadProfilePhotoIfNeeded(_ data: Data?, uid: String) async throws -> (url: String?, updatedAt: Date, data: Data)? {
        guard let data, !data.isEmpty else { return nil }
        guard let preparedData = await ProfilePhotoImageProcessor.preparedJPEGData(from: data) else {
            throw AuthenticationError.profileSaveFailed
        }

        #if canImport(FirebaseStorage)
        let reference = Storage.storage().reference().child("users/\(uid)/profile/profile.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        do {
            _ = try await reference.putDataAsync(preparedData, metadata: metadata)
            let downloadURL = try await reference.downloadURL()
            let updatedAt = Date()
            _ = try await ProfilePhotoLocalStore.save(preparedData, uid: uid, updatedAt: updatedAt)
            WanderlustDiagnostics.info("profile photo upload completed", category: .sync)
            return (downloadURL.absoluteString, updatedAt, preparedData)
        } catch {
            let nsError = error as NSError
            WanderlustDiagnostics.warning(
                "profile photo upload failed domain=\(nsError.domain) code=\(nsError.code)",
                category: .sync
            )
            let updatedAt = Date()
            _ = try? await ProfilePhotoLocalStore.save(preparedData, uid: uid, updatedAt: updatedAt)
            return (nil, updatedAt, preparedData)
        }
        #else
        let updatedAt = Date()
        _ = try? await ProfilePhotoLocalStore.save(preparedData, uid: uid, updatedAt: updatedAt)
        return (nil, updatedAt, preparedData)
        #endif
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            for random in randoms {
                if remaining == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func wanderlustUser(
        from user: FirebaseAuth.User,
        fallbackName: String? = nil,
        fallbackEmail: String? = nil
    ) -> WanderlustUser {
        let providerID = user.providerData.first?.providerID ?? ""
        let accountType: String
        if providerID == "google.com" { accountType = "google" }
        else if providerID == "apple.com" { accountType = "apple" }
        else { accountType = "email" }
        return WanderlustUser(
            id: user.uid,
            name: user.displayName ?? fallbackName ?? "",
            email: user.email ?? fallbackEmail ?? "",
            homeCountryISO2: nil,
            profilePhotoData: nil,
            profilePhotoURL: nil,
            isLocalOnly: false,
            isEmailVerified: user.isEmailVerified,
            accountType: accountType,
            creationDate: user.metadata.creationDate,
            lastSignInDate: user.metadata.lastSignInDate,
            profileCompleted: false
        )
    }
}

private struct DuplicateSignInMethodError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static var retainKey = 0
    private let continuation: CheckedContinuation<ASAuthorization, Error>
    private let window: UIWindow

    init(continuation: CheckedContinuation<ASAuthorization, Error>, window: UIWindow) {
        self.continuation = continuation
        self.window = window
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation.resume(returning: authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == ASAuthorizationError.errorDomain, nsError.code == ASAuthorizationError.canceled.rawValue {
            continuation.resume(throwing: AuthenticationError.appleSignInCancelled)
        } else {
            continuation.resume(throwing: error)
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window
    }
}
#endif

#if canImport(FirebaseFirestore)
private struct FirebaseProfileDocument {
    let name: String
    let email: String
    let homeCountryISO2: String?
    let profilePhotoURL: String?
    let profilePhotoData: Data?
    let profilePhotoUpdatedAt: Date?
    let accountType: String
    let profileCompleted: Bool

    init(data: [String: Any]) {
        name = data["displayName"] as? String ?? data["name"] as? String ?? ""
        email = data["email"] as? String ?? ""
        homeCountryISO2 = data["homeCountryISO2"] as? String
        profilePhotoURL = data["profilePhotoURL"] as? String
        if let base64 = data["profilePhotoData"] as? String {
            profilePhotoData = Data(base64Encoded: base64)
        } else {
            profilePhotoData = nil
        }
        if let timestamp = data["profilePhotoUpdatedAt"] as? Timestamp {
            profilePhotoUpdatedAt = timestamp.dateValue()
        } else {
            profilePhotoUpdatedAt = nil
        }
        accountType = data["accountType"] as? String ?? "email"
        profileCompleted = (data["profileCompleted"] as? Bool) ??
            FirebaseAuthenticationService.isProfileComplete(
                name: name,
                homeCountryISO2: homeCountryISO2,
                profilePhotoURL: profilePhotoURL,
                profilePhotoData: profilePhotoData
            )
    }
}
#endif

enum ProfilePhotoLocalStore {
    nonisolated private static let folderName = "ProfilePhotos"

    static func save(_ data: Data?, uid: String, updatedAt: Date? = nil) async throws -> Data? {
        guard let data, !data.isEmpty else { return nil }
        guard let preparedData = await ProfilePhotoImageProcessor.preparedJPEGData(from: data) else {
            return nil
        }

        try await Task.detached(priority: .utility) {
            let url = try fileURL(uid: uid)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try preparedData.write(to: url, options: [.atomic])
            if let updatedAt {
                try? FileManager.default.setAttributes([.modificationDate: updatedAt], ofItemAtPath: url.path)
            }
        }.value

        return preparedData
    }

    static func loadData(uid: String) async -> Data? {
        await Task.detached(priority: .utility) {
            guard let url = try? fileURL(uid: uid) else { return nil }
            return try? Data(contentsOf: url)
        }.value
    }

    static func updatedAt(uid: String) async -> Date? {
        await Task.detached(priority: .utility) {
            guard let url = try? fileURL(uid: uid),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
                return nil
            }
            return attributes[.modificationDate] as? Date
        }.value
    }

    static func delete(uid: String) async throws {
        try await Task.detached(priority: .utility) {
            let url = try fileURL(uid: uid)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }.value
    }

    nonisolated private static func fileURL(uid: String) throws -> URL {
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let safeUID = uid
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return supportDirectory
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("\(safeUID).jpg")
    }
}

private enum ProfilePhotoImageProcessor {
    static func preparedJPEGData(from data: Data, maxDimension: CGFloat = 1_024) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { return nil }
            let normalized = image.normalizedForProfilePhotoStorage()
            let resized = normalized.resizedForProfilePhotoStorage(maxDimension: maxDimension)
            return resized.jpegData(compressionQuality: 0.82)
        }.value
    }
}

private extension UIImage {
    nonisolated func normalizedForProfilePhotoStorage() -> UIImage {
        guard imageOrientation != .up else { return self }
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    nonisolated func resizedForProfilePhotoStorage(maxDimension: CGFloat) -> UIImage {
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

@MainActor
private extension UIApplication {
    func wanderlustTopViewController() -> UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .wanderlustTopPresentedViewController()
    }
}

@MainActor
private extension UIViewController {
    func wanderlustTopPresentedViewController() -> UIViewController {
        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.wanderlustTopPresentedViewController()
        }

        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.wanderlustTopPresentedViewController()
        }

        if let presentedViewController {
            return presentedViewController.wanderlustTopPresentedViewController()
        }

        return self
    }
}

private enum FirebaseAppGuard {
    static var isConfigured: Bool {
        #if canImport(FirebaseCore)
        return FirebaseApp.app() != nil
        #else
        return false
        #endif
    }
}

@MainActor
final class LocalAuthenticationService: AuthenticationService {
    private enum Keys {
        static let user = "atlas.auth.localUser"
    }

    private(set) var currentUser: WanderlustUser?

    init() {
        currentUser = Self.loadUser()
    }

    func createAccount(
        name: String,
        email: String,
        password: String,
        homeCountryISO2: String?,
        profilePhotoData: Data?
    ) async throws -> WanderlustUser {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else {
            throw AuthenticationError.invalidCredentials
        }
        guard WanderlustPasswordPolicy.isValid(password) else {
            throw AuthenticationError.passwordDoesNotMeetRequirements
        }

        let user = WanderlustUser(
            id: UUID().uuidString,
            name: trimmedName,
            email: trimmedEmail,
            homeCountryISO2: homeCountryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            profilePhotoData: profilePhotoData,
            isLocalOnly: true,
            isEmailVerified: false,
            accountType: "local",
            creationDate: Date(),
            lastSignInDate: Date(),
            profileCompleted: false
        )
        try save(user)
        currentUser = user
        return user
    }

    func signIn(email: String, password: String) async throws -> WanderlustUser {
        let savedUser = currentUser ?? Self.loadUser()
        guard var user = savedUser,
              user.email.localizedCaseInsensitiveCompare(email.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame,
              password.count >= 8 else {
            throw AuthenticationError.invalidCredentials
        }
        user.lastSignInDate = Date()
        try save(user)
        currentUser = user
        return user
    }

    func signInWithGoogle() async throws -> WanderlustUser {
        throw AuthenticationError.googleSignInUnavailable
    }

    func signInWithApple() async throws -> WanderlustUser {
        throw AuthenticationError.appleSignInUnavailable
    }

    func signOut() async throws {
        currentUser = nil
    }

    func reauthenticateAndDelete(credential: ReauthCredential) async throws {
        throw AuthenticationError.backendUnavailable
    }

    func deleteAccount() async throws {
        UserDefaults.standard.removeObject(forKey: Keys.user)
        currentUser = nil
    }

    func resetPassword(email: String) async throws {
        throw AuthenticationError.passwordResetUnavailable
    }

    func sendEmailVerification() async throws {
        throw AuthenticationError.backendUnavailable
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        throw AuthenticationError.passwordResetUnavailable
    }

    func changeEmail(newEmail: String, currentPassword: String) async throws {
        throw AuthenticationError.passwordResetUnavailable
    }

    func reloadCurrentUser() async throws -> WanderlustUser? {
        currentUser
    }

    func updateProfile(name: String, homeCountryISO2: String?, profilePhotoData: Data?) async throws -> WanderlustUser {
        guard var user = currentUser else {
            throw AuthenticationError.invalidCredentials
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AuthenticationError.invalidCredentials
        }
        user.name = trimmedName
        user.homeCountryISO2 = homeCountryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        user.profileCompleted = true
        user.profilePhotoData = profilePhotoData?.isEmpty == false ? profilePhotoData : nil
        try save(user)
        currentUser = user
        return user
    }

    func syncSettings(appearance: String, homeCountryHighlight: Bool, homeCountryISO2: String?) async throws {
        guard var user = currentUser else { return }
        user.homeCountryISO2 = homeCountryISO2?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        try save(user)
        currentUser = user
    }

    func migrateLocalDataToCurrentAccount() async throws {
        _ = TripStore.shared.save()
    }

    private func save(_ user: WanderlustUser) throws {
        let data = try JSONEncoder().encode(user)
        UserDefaults.standard.set(data, forKey: Keys.user)
    }

    private static func loadUser() -> WanderlustUser? {
        guard let data = UserDefaults.standard.data(forKey: Keys.user) else {
            return nil
        }
        return try? JSONDecoder().decode(WanderlustUser.self, from: data)
    }
}
