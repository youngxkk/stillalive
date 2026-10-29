import SwiftUI
import MessageUI
import PhotosUI

struct ContactView: View {
    @ObservedObject var manager: AliveManager
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("hapticsEnabled") var hapticsEnabled = true

    @State private var showMailView = false
    @State private var showErrorAlert = false
    @State private var mailResult: Result<MFMailComposeResult, Error>? = nil
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var feedbackCount = 0
    @State private var photoItem: PhotosPickerItem?
    // Contact photo stays on this device only and is never synced
    @AppStorage("contactAvatar") private var avatarData: Data?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, subject, body
    }

    private enum TestResult {
        case sent, failed
    }

    private var trimmedEmail: String {
        manager.contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmailValid: Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: trimmedEmail)
    }

    private var isReady: Bool {
        !trimmedEmail.isEmpty && isEmailValid
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground(status: .safe)
                    .ignoresSafeArea()

                NoiseTexture()
                    .opacity(colorScheme == .dark ? 0.12 : 0.05)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        hero

                        recipientCard

                        messageCard

                        testSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Emergency Contact")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundColor(.primary)
                        .opacity(0.9)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .sensoryFeedback(trigger: feedbackCount) { _, _ in
                hapticsEnabled ? .success : nil
            }
            .sheet(isPresented: $showMailView) {
                MailView(result: $mailResult, recipients: [trimmedEmail], subject: manager.emailSubject, body: manager.emailBody)
            }
            .onChange(of: manager.syncStatus) { _, status in
                guard isTesting else { return }
                switch status {
                case .success:
                    testResult = .sent
                    feedbackCount += 1
                case .failed:
                    testResult = .failed
                default:
                    break
                }
            }
            .onDisappear {
                // Push contact changes to the server so an old contact never receives an alert
                guard manager.contactEmail.isEmpty || isEmailValid else { return }
                Task {
                    await manager.syncContactSettings()
                }
            }
            .alert(NSLocalizedString("Mail_Config_Error_Title", comment: ""), isPresented: $showErrorAlert) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("Mail_Config_Error_Message", comment: ""))
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        let color = isReady ? statusColor(.safe) : statusColor(.warning)

        return HStack(spacing: 16) {
            avatar

            VStack(alignment: .leading, spacing: 6) {
                if isReady {
                    Text(trimmedEmail)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Contact_Not_Set")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                }

                Label(isReady ? LocalizedStringKey("Contact_Ready") : LocalizedStringKey("Sync_Status_NoEmail"),
                      systemImage: isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .glassCard(cornerRadius: 26, highlight: cardHighlight)
    }

    private var avatar: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(colors: [accent, accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            if let initial = avatarInitial {
                                Text(initial)
                                    .font(.system(size: 26, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .topLeading, endPoint: .center), lineWidth: 1.5)
                }
                .shadow(color: accent.opacity(0.35), radius: 12, x: 0, y: 6)

                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.background))
                    .overlay(Circle().stroke(accent.opacity(0.3), lineWidth: 1))
                    .offset(x: 2, y: 2)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .contextMenu {
            if avatarData != nil {
                Button("Contact_Remove_Photo", systemImage: "trash", role: .destructive) {
                    avatarData = nil
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    avatarData = resizedAvatar(image)
                }
                photoItem = nil
            }
        }
        .accessibilityLabel(Text("Contact_Change_Photo"))
    }

    // MARK: - Recipient

    private var recipientCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("Recipient Email", systemImage: "envelope.fill")

            HStack(spacing: 10) {
                TextField("Contact_Email_Placeholder", text: $manager.contactEmail)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .subject }

                if !manager.contactEmail.isEmpty {
                    Image(systemName: isEmailValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(isEmailValid ? statusColor(.safe) : statusColor(.danger))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(fieldBorder, lineWidth: 1)
                    }
            }
            .animation(.snappy, value: isEmailValid)
            .animation(.snappy, value: manager.contactEmail.isEmpty)

            Group {
                if !manager.contactEmail.isEmpty && !isEmailValid {
                    Label("Invalid_Email", systemImage: "exclamationmark.circle")
                        .foregroundStyle(statusColor(.danger))
                } else {
                    Text("This email will be used when the timer expires.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 26, highlight: cardHighlight)
    }

    private var fieldBorder: Color {
        if focusedField == .email { return accent.opacity(0.6) }
        if !manager.contactEmail.isEmpty && !isEmailValid { return statusColor(.danger).opacity(0.5) }
        return Color.primary.opacity(0.08)
    }

    // MARK: - Message

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                cardHeader("Message Content", systemImage: "text.bubble.fill")
                Spacer()
                if !manager.emailSubject.isEmpty || !manager.emailBody.isEmpty {
                    Button {
                        withAnimation(.snappy) {
                            manager.emailSubject = ""
                            manager.emailBody = ""
                        }
                    } label: {
                        Label("Contact_Use_Default", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                TextField("Subject", text: $manager.emailSubject, prompt: Text("Default_Email_Subject"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .subject)
                    .onSubmit { focusedField = .body }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)

                Divider()
                    .padding(.horizontal, 16)

                TextField("Enter message body...", text: $manager.emailBody, prompt: Text("Default_Email_Body"), axis: .vertical)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .lineLimit(6...)
                    .focused($focusedField, equals: .body)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
            }
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(focusedField == .subject || focusedField == .body ? accent.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(statusColor(.warning))
                Text("Email_Body_Hint")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 26, highlight: cardHighlight)
    }

    // MARK: - Test

    private var testSection: some View {
        VStack(spacing: 12) {
            Text("Contact_Test_Title")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundStyle(Color.primary.opacity(0.45))

            Button {
                focusedField = nil
                testResult = nil
                Task {
                    isTesting = true
                    await manager.sendTestEmailToServer()
                    isTesting = false
                }
            } label: {
                HStack(spacing: 10) {
                    if isTesting && manager.syncStatus == .syncing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text("Contact_Test_Server")
                    }
                }
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background {
                    Capsule()
                        .fill(LinearGradient(colors: [accent, accent.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay {
                            Capsule()
                                .stroke(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .topLeading, endPoint: .center), lineWidth: 1.5)
                        }
                        .shadow(color: accent.opacity(0.4), radius: 20, x: 0, y: 12)
                }
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!canTestViaServer)
            .opacity(canTestViaServer ? 1 : 0.4)

            Button {
                focusedField = nil
                if MFMailComposeViewController.canSendMail() {
                    showMailView = true
                } else {
                    showErrorAlert = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.open.fill")
                    Text("Contact_Test_Mail_App")
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        }
                }
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!isReady)
            .opacity(isReady ? 1 : 0.4)

            testFooter
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .animation(.snappy, value: testResult)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var testFooter: some View {
        switch testResult {
        case .sent:
            Label("Test_Email_Sent_Success", systemImage: "checkmark.circle.fill")
                .foregroundStyle(statusColor(.safe))
        case .failed:
            Label("Test_Email_Sent_Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(statusColor(.danger))
        case nil:
            if manager.canSendTestEmail() {
                Text("Test_Limit_Description")
                    .foregroundStyle(.secondary)
            } else {
                Label(String(format: NSLocalizedString("Contact_Test_Next", comment: ""), nextTestText), systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var canTestViaServer: Bool {
        isReady && manager.canSendTestEmail() && manager.syncStatus != .syncing
    }

    private var avatarInitial: String? {
        guard isReady, let first = trimmedEmail.first else { return nil }
        return String(first).uppercased()
    }

    private var avatarImage: UIImage? {
        avatarData.flatMap(UIImage.init(data:))
    }

    /// Downscale so the stored photo stays small
    private func resizedAvatar(_ image: UIImage) -> Data? {
        let side: CGFloat = 240
        let scale = side / min(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    private var nextTestText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        return formatter.string(from: max(60, manager.timeUntilNextTestAllowed)) ?? ""
    }

    private func cardHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .tracking(2)
            .foregroundStyle(Color.primary.opacity(0.45))
    }

    /// Whiter cards so they read clearly over the background
    private var cardHighlight: Double {
        colorScheme == .dark ? 0.08 : 0.55
    }

    /// Warm rose used for the people who look out for you
    private var accent: Color {
        colorScheme == .dark ? Color(hex: "FF7AA2") : Color(hex: "D9466F")
    }

    private func statusColor(_ status: AliveManager.AliveStatus) -> Color {
        if colorScheme == .dark {
            switch status {
            case .safe: return Color(hex: "00F260")
            case .warning: return Color(hex: "FFB347")
            case .danger: return Color(hex: "FF4B2B")
            }
        } else {
            switch status {
            case .safe: return Color(hex: "1D976C")
            case .warning: return Color(hex: "E67E22")
            case .danger: return Color(hex: "C0392B")
            }
        }
    }
}

#Preview {
    ContactView(manager: AliveManager())
}
