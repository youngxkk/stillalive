import SwiftUI
import MessageUI

struct ContactView: View {
    @ObservedObject var manager: AliveManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showMailView = false
    @State private var showErrorAlert = false
    @State private var mailResult: Result<MFMailComposeResult, Error>? = nil
    
    var isEmailValid: Bool {
        let trimmed = manager.contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: trimmed)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Emergency Contact"), footer: Text("This email will be used when the timer expires.")) {
                    VStack(alignment: .leading) {
                        TextField("Recipient Email", text: $manager.contactEmail)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        
                        if !manager.contactEmail.isEmpty && !isEmailValid {
                            Text("Invalid_Email")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section(header: Text("Message Content"), footer: Text("Email_Body_Hint")) {
                    TextField("Subject", text: $manager.emailSubject)
                    
                    ZStack(alignment: .topLeading) {
                        if manager.emailBody.isEmpty {
                            Text(NSLocalizedString("Default_Email_Body", comment: ""))
                                .foregroundColor(Color.primary.opacity(0.3))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $manager.emailBody)
                            .frame(minHeight: 180)
                    }
                }
                
                Section(footer: Text("Test_Limit_Description")) {
                     Button(action: {
                         Task {
                             await manager.sendTestEmailToServer()
                         }
                     }) {
                         HStack {
                             Image(systemName: "server.rack")
                             Text("Test_Via_Server")
                         }
                     }
                     .disabled(manager.contactEmail.isEmpty || !isEmailValid || !manager.canSendTestEmail() || manager.syncStatus == .syncing)
                     
                     Button(action: {
                         if MFMailComposeViewController.canSendMail() {
                             showMailView = true
                         } else {
                             showErrorAlert = true
                         }
                     }) {
                         HStack {
                             Image(systemName: "envelope")
                             Text("Send Test Email")
                         }
                     }
                     .disabled(manager.contactEmail.isEmpty || !isEmailValid)
                 }
            }
            .navigationTitle("Emergency Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showMailView) {
                MailView(result: $mailResult, recipients: [manager.contactEmail], subject: manager.emailSubject, body: manager.emailBody)
            }
            .alert(NSLocalizedString("Mail_Config_Error_Title", comment: ""), isPresented: $showErrorAlert) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("Mail_Config_Error_Message", comment: ""))
            }
        }
    }
}

#Preview {
    ContactView(manager: AliveManager())
}
