import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Your drawings stay with you") {
                Text("InfinityPaper does not collect or transmit your drawings, reference images, or personal data to the developer. The app has no account system, advertising, analytics SDKs, or tracking.")
            }
            Section("Local storage") {
                Text("Drawings, reference images, and previews are stored in the app’s local storage. Brush choices and other preferences are saved on your device. Device backups may include this data according to your Apple backup settings.")
            }
            Section("Photos, files & sharing") {
                Text("The app imports only the images you choose through Apple’s Photos or Files picker. Imported images are resized and saved with the drawing. When you export or share, the file is sent to the app, person, or location you choose. Those services handle it under their own policies.")
            }
            Section("Deleting data") {
                Text("Delete a drawing from My drawings to remove its locally stored content. Removing the app removes its local app data. Copies you exported, shared, or backed up are managed separately.")
            }
            Section("Contact & published policy") {
                if let policyURL = AppLinks.privacyPolicy {
                    Link("Read the published privacy policy", destination: policyURL)
                }
                if let supportURL = AppLinks.support {
                    Link("Contact support", destination: supportURL)
                }
            }
            Section("Policy updates") {
                Text("This policy describes this version of InfinityPaper. If the app’s data practices change, its privacy policy and App Store disclosures will be updated.")
            }
        }
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
