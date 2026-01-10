import SwiftUI
import MessageUI

struct ContactView: View {
    @ObservedObject var manager: AliveManager
    @Environment(\.dismiss) var dismiss
    
    @State private var showMailView = false
    @State private var showErrorAlert = false
    @State private var mailResult: Result<MFMailComposeResult, Error>? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Emergency Contact"), footer: Text("This email will be used when the timer expires.")) {
                    TextField("Recipient Email", text: $manager.contactEmail)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                
                Section(header: Text("Message Content")) {
                    TextField("Subject", text: $manager.emailSubject)
                    
                    ZStack(alignment: .topLeading) {
                        if manager.emailBody.isEmpty {
                            Text("Enter message body...")
                                .foregroundColor(Color.gray.opacity(0.5))
                                .padding(.top, 8)
                        }
                        TextEditor(text: $manager.emailBody)
                            .frame(minHeight: 100)
                    }
                }
                
                Section {
                     Button(action: {
                         if MFMailComposeViewController.canSendMail() {
                             showMailView = true
                         } else {
                             showErrorAlert = true
                             print("Can't send mail")
                         }
                     }) {
                         HStack {
                             Image(systemName: "envelope.fill")
                             Text("Send Test Email")
                         }
                     }
                     .disabled(manager.contactEmail.isEmpty)
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
