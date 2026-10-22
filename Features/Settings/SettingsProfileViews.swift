import SwiftUI
import PhotosUI
import Photos
import UIKit
import AVFoundation

struct EditProfileSheet: View {
    @Binding var username: String
    @Binding var homeCountry: String
    @Binding var profilePhotoData: Data
    var onProfilePhotoSaved: (@MainActor (Data) async -> Data)? = nil
    var onProfilePhotoDeleted: (@MainActor () async -> Void)? = nil

    @StateObject private var authenticationStore = AuthenticationStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draftUsername = ""
    @State private var draftHomeCountry = ""
    @State private var draftPhotoData = Data()
    @State private var didInitialize = false
    @State private var showProfilePhotoSavedToast = false
    @State private var profilePhotoToastText = ""
    @State private var profilePhotoSavedToastTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
    }

    private var selectedCountry: Country? {
        GeoJSONLoader.shared.country(withISOCode: draftHomeCountry) ??
            GeoJSONLoader.shared.country(named: draftHomeCountry)
    }

    private var hasChanges: Bool {
        draftUsername != username ||
            draftHomeCountry != homeCountry ||
            draftPhotoData != profilePhotoData
    }

    var body: some View {
        Form {
            Section {
                SettingsProfilePhotoPicker(
                    profilePhotoData: $draftPhotoData,
                    onProfilePhotoSaved: { data in
                        let savedData = await onProfilePhotoSaved?(data) ?? data
                        profilePhotoData = savedData
                        draftPhotoData = savedData
                        try? await Task.sleep(for: .milliseconds(250))
                        showProfilePhotoToast(
                            WanderlustL10n.string(
                                "Profile photo saved.",
                                table: .settings,
                                fallback: "Profile photo saved."
                            )
                        )
                        return savedData
                    },
                    onProfilePhotoDeleted: {
                        profilePhotoData = Data()
                        draftPhotoData = Data()
                        await onProfilePhotoDeleted?()
                        if authenticationStore.authenticationState == .signedIn {
                            _ = await authenticationStore.updateProfile(
                                name: draftUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                                homeCountryISO2: selectedCountry?.isoCode ?? draftHomeCountry,
                                profilePhotoData: nil
                            )
                        }
                        try? await Task.sleep(for: .milliseconds(250))
                        showProfilePhotoToast(
                            WanderlustL10n.string(
                                "Profile photo deleted.",
                                table: .account,
                                fallback: "Profile photo deleted."
                            )
                        )
                    }
                )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section(WanderlustL10n.string("Username", table: .account)) {
                TextField(WanderlustL10n.string("Username not set", table: .account), text: $draftUsername)
                        .textContentType(.nickname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
            }

            Section(WanderlustL10n.string("Home Country", table: .account)) {
                NavigationLink {
                    HomeCountryPickerView(homeCountry: $draftHomeCountry)
                } label: {
                    HStack(spacing: 12) {
                        Text(selectedCountry?.flagEmoji ?? "🌍")
                            .font(.title2)
                        Text(selectedCountry?.displayName ?? WanderlustL10n.string("Not Set", table: .settings))
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(WanderlustL10n.string("Edit Profile", table: .account))
        .toolbarTitleDisplayMode(.inline)
        .onAppear {
            guard !didInitialize else { return }
            didInitialize = true
            draftUsername = username
            draftHomeCountry = homeCountry
            draftPhotoData = profilePhotoData
        }
        .overlay(alignment: .bottom) {
            if showProfilePhotoSavedToast {
                SettingsSavedToast(
                    text: profilePhotoToastText
                )
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showProfilePhotoSavedToast)
        .onDisappear {
            profilePhotoSavedToastTask?.cancel()
            profilePhotoSavedToastTask = nil
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save")) {
                    let newName = draftUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                    let newHomeCountry = selectedCountry?.isoCode ?? draftHomeCountry
                    username = newName
                    homeCountry = newHomeCountry
                    profilePhotoData = draftPhotoData
                    focusedField = nil
                    if authenticationStore.authenticationState == .signedIn {
                        Task {
                            _ = await authenticationStore.updateProfile(
                                name: newName,
                                homeCountryISO2: newHomeCountry,
                                profilePhotoData: draftPhotoData.isEmpty ? nil : draftPhotoData
                            )
                        }
                    }
                    dismiss()
                }
                .tint(.blue)
                .fontWeight(.regular)
                .disabled(!hasChanges)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "Done")) {
                    focusedField = nil
                }
            }
        }
    }

    private func showProfilePhotoToast(_ text: String) {
        profilePhotoToastText = text
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
}

struct SettingsSavedToast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
            .accessibilityAddTraits(.isStaticText)
    }
}

struct HomeCountrySettingsView: View {
    @Binding var homeCountry: String

    private var selectedCountry: Country? {
        let cleaned = homeCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        return GeoJSONLoader.shared.country(withISOCode: cleaned) ??
            GeoJSONLoader.shared.country(named: cleaned)
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    HomeCountryPickerView(homeCountry: $homeCountry)
                } label: {
                    HStack(spacing: 12) {
                        Text(selectedCountry?.flagEmoji ?? "🌍")
                            .font(.title2)
                        Text(selectedCountry?.displayName ?? WanderlustL10n.string("Not Set", table: .settings))
                        Spacer()
                    }
                }
            } header: {
                Text(WanderlustL10n.string("Home Country", table: .account))
            } footer: {
                Text(WanderlustL10n.string("Show your home country highlighted on the map.", table: .account))
            }
        }
        .navigationTitle(WanderlustL10n.string("Home Country", table: .account))
        .toolbarTitleDisplayMode(.inline)
        .onAppear {
            GeoJSONLoader.shared.loadIfNeeded()
            homeCountry = selectedCountry?.isoCode ?? homeCountry
        }
    }
}

struct SettingsProfilePhotoPicker: View {
    @Binding var profilePhotoData: Data
    var onProfilePhotoSaved: (@MainActor (Data) async -> Data)? = nil
    var onProfilePhotoDeleted: (@MainActor () async -> Void)? = nil
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoading = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showPhotoActions = false
    @State private var showPhotoDeniedAlert = false
    @State private var showCameraDeniedAlert = false
    @State private var selectedImage: UIImage?
    @State private var showCropper = false

    private var actionTitle: String {
        WanderlustL10n.string("Edit Photo", table: .account, fallback: "Edit Photo")
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let image = UIImage(data: profilePhotoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))

            Button {
                showPhotoActions = true
            } label: {
                if isLoading {
                    ProgressView()
                } else {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .disabled(isLoading)
        }
        .confirmationDialog(
            WanderlustL10n.string("Profile Photo", table: .account, fallback: "Profile Photo"),
            isPresented: $showPhotoActions,
            titleVisibility: .visible
        ) {
            Button(WanderlustL10n.string("Choose from Library", table: .account, fallback: "Choose Photo")) {
                requestPhotoPickerIfNeeded()
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button(WanderlustL10n.string("Take Photo", table: .account, fallback: "Take Photo")) {
                    requestCameraIfNeeded()
                }
            }

            if !profilePhotoData.isEmpty {
                Button(WanderlustL10n.string("Delete Photo", table: .account, fallback: "Remove Profile Photo"), role: .destructive) {
                    deleteProfilePhoto()
                }
            }

            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickerItem,
            matching: .images
        )
        .sheet(isPresented: $showCamera) {
            SettingsCameraImagePicker { image in
                showCamera = false
                Task { @MainActor in
                    await Task.yield()
                    prepareSelectedImage(image)
                }
            } onCancel: {
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showCropper) {
            if let selectedImage {
                PhotoCropView(image: selectedImage) { croppedImage in
                    if let data = croppedImage.jpegData(compressionQuality: 0.84) {
                        profilePhotoData = data
                        if let onProfilePhotoSaved {
                            Task {
                                profilePhotoData = await onProfilePhotoSaved(data)
                            }
                        }
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
            WanderlustL10n.string("Camera Access Needed", table: .errors, fallback: "Camera Access Needed"),
            isPresented: $showCameraDeniedAlert
        ) {
            Button(WanderlustL10n.string("Open Settings", table: .settings)) {
                openAppSettings()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
                .tint(.blue)
                .fontWeight(.regular)
        } message: {
            Text(WanderlustL10n.string("Allow camera access in iPhone Settings to take a profile photo.", table: .account, fallback: "Allow camera access in iPhone Settings to take a profile photo."))
        }
        .onChange(of: pickerItem) {
            guard let pickerItem else { return }
            isLoading = true
            Task {
                let data = try? await pickerItem.loadTransferable(type: Data.self)
                let image = data.flatMap(UIImage.init(data:))?
                    .normalizedOrientation()
                    .resized(toMaxDimension: 1_600)
                await MainActor.run {
                    if let image {
                        selectedImage = image
                        showCropper = true
                    }
                    self.pickerItem = nil
                    isLoading = false
                }
            }
        }
    }

    private func requestPhotoPickerIfNeeded() {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            showPhotoPicker = true
        case .notDetermined:
            Task {
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                await MainActor.run {
                    if status == .authorized || status == .limited {
                        showPhotoPicker = true
                    } else {
                        showPhotoDeniedAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showPhotoDeniedAlert = true
        @unknown default:
            showPhotoDeniedAlert = true
        }
    }

    private func requestCameraIfNeeded() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run {
                    if granted {
                        showCamera = true
                    } else {
                        showCameraDeniedAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraDeniedAlert = true
        @unknown default:
            showCameraDeniedAlert = true
        }
    }

    private func prepareSelectedImage(_ image: UIImage) {
        selectedImage = image
            .normalizedOrientation()
            .resized(toMaxDimension: 1_600)
        showCropper = true
    }

    private func deleteProfilePhoto() {
        profilePhotoData = Data()
        if let onProfilePhotoDeleted {
            Task {
                await onProfilePhotoDeleted()
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

private struct SettingsCameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImagePicked: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImagePicked = onImagePicked
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

struct HomeCountryPickerView: View {
    @Binding var homeCountry: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var cleanQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var countries: [Country] {
        if cleanQuery.isEmpty {
            return GeoJSONLoader.shared.countries.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }

        return GeoJSONLoader.shared.searchCountries(query: cleanQuery, limit: 30)
    }

    var body: some View {
        List(countries) { country in
            Button {
                withTransaction(Transaction(animation: nil)) {
                    homeCountry = country.isoCode
                }
                query = ""
                isSearchFocused = false
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Text(country.flagEmoji)
                        .font(.title2)
                    Text(country.displayName)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(WanderlustL10n.string("Home Country", table: .account))
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: WanderlustL10n.string("Search Countries", table: .world))
        .focused($isSearchFocused)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            GeoJSONLoader.shared.loadIfNeeded()
        }
    }
}
