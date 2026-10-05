import SwiftUI

struct SettingsView: View {
    @Environment(ShelfModel.self) private var model
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                if let session = model.session {
                    Section("Account") {
                        LabeledContent("Username", value: session.username)
                        LabeledContent("Server", value: session.serverURL)
                        if let version = session.kavitaVersion, !version.isEmpty {
                            LabeledContent("Kavita", value: version)
                        }
                    }
                }

                Section {
                    Picker("Reading direction", selection: Bindable(model).readingDirection) {
                        ForEach(ReadingDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                } header: {
                    Text("Comics and PDF")
                } footer: {
                    Text("Right to left is for manga. EPUBs follow the book’s own order. Progress is saved through Kavita’s KOReader sync, so a Kindle running KOReader stays on the same page.")
                }

                Section {
                    Toggle("Allow untrusted certificates", isOn: Bindable(model).allowUntrustedCertificates)
                } footer: {
                    Text("Use this for a self-signed HTTPS certificate on your Kavita server.")
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        confirmSignOut = true
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sign out of Kavita?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { model.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Shelf removes the saved server, password, and tokens from the Keychain.")
            }
        }
    }
}
