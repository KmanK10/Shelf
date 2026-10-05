import SwiftUI

struct LoginView: View {
    @Environment(ShelfModel.self) private var model
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server", text: $server, prompt: Text("https://kavita.example"))
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Kavita")
                } footer: {
                    Text("Kavita signs in with your username. Shelf stores the server, password, JWT, refresh token, and API key in the iOS Keychain.")
                }

                Section {
                    Toggle("Allow untrusted certificates", isOn: Bindable(model).allowUntrustedCertificates)
                } footer: {
                    Text("Turn this on for a Kavita server that uses a self-signed HTTPS certificate.")
                }

                if let message = errorMessage ?? model.loginMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Shelf")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign In") { signIn() }
                        .disabled(!canSubmit)
                }
            }
            .overlay {
                if isSigningIn {
                    ProgressView("Signing in")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .onAppear {
                if server.isEmpty { server = model.prefilledServer }
                if username.isEmpty { username = model.prefilledUsername }
            }
        }
    }

    private var canSubmit: Bool {
        !isSigningIn
            && !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private func signIn() {
        errorMessage = nil
        isSigningIn = true
        Task {
            do {
                try await model.signIn(server: server, username: username, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}
