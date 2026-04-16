import AuthenticationServices
import SwiftUI

struct LoginView: View {

    @ObservedObject var authService: AuthService
    @State private var screen: LoginScreen = .welcome

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.04, blue: 0.12),
                    Color(red: 0.05, green: 0.08, blue: 0.20),
                    Color(red: 0.03, green: 0.06, blue: 0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            floatingOrbs

            VStack(spacing: 0) {
                switch screen {
                case .welcome:
                    welcomeScreen
                case .signIn:
                    AuthFormScreen(
                        title: "Welcome back",
                        subtitle: nil,
                        buttonText: "Sign In",
                        showName: false,
                        authService: authService,
                        onBack: { withAnimation(.spring) { screen = .welcome } },
                        onSubmit: { email, password, _, _ in
                            await authService.login(email: email, password: password)
                        }
                    )
                case .createAccount:
                    AuthFormScreen(
                        title: "Create your account",
                        subtitle: "Start exploring the world",
                        buttonText: "Create Account",
                        showName: true,
                        authService: authService,
                        onBack: { withAnimation(.spring) { screen = .welcome } },
                        onSubmit: { email, password, name, username in
                            await authService.register(email: email, password: password, name: name, username: username)
                        }
                    )
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: screen)
        }
    }

    private var welcomeScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            OrbiLogoDark(size: 130, showText: false)
                .padding(.bottom, 12)

            Text("Orbi")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Travel, reimagined.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 4)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    withAnimation(.spring) { screen = .createAccount }
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.0, green: 0.75, blue: 0.85), Color(red: 0.2, green: 0.5, blue: 1.0)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .cyan.opacity(0.3), radius: 12, y: 6)
                }

                Button {
                    withAnimation(.spring) { screen = .signIn }
                } label: {
                    Text("I already have an account")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                #if DEBUG
                Button {
                    Task {
                        await authService.register(email: "debug@orbi.app", password: "debug123456", name: "Debug")
                        if !authService.isAuthenticated {
                            await authService.login(email: "debug@orbi.app", password: "debug123456")
                        }
                    }
                } label: {
                    Text("Quick Login (Debug)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.top, 4)
                }
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
    }

    private var floatingOrbs: some View {
        ZStack {
            Circle().fill(Color.cyan.opacity(0.08)).frame(width: 300, height: 300).blur(radius: 60).offset(x: -80, y: -200)
            Circle().fill(Color.blue.opacity(0.06)).frame(width: 250, height: 250).blur(radius: 50).offset(x: 100, y: 100)
            Circle().fill(Color.purple.opacity(0.05)).frame(width: 200, height: 200).blur(radius: 40).offset(x: -50, y: 300)
        }
    }
}

enum LoginScreen: Equatable {
    case welcome, signIn, createAccount
}

// MARK: - Reusable Auth Form

struct AuthFormScreen: View {
    let title: String
    let subtitle: String?
    let buttonText: String
    let showName: Bool
    @ObservedObject var authService: AuthService
    let onBack: () -> Void
    let onSubmit: (String, String, String?, String?) async -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                VStack(spacing: 14) {
                    if showName {
                        fieldRow(icon: "person.fill", placeholder: "Your name", text: $name)
                        fieldRow(icon: "at", placeholder: "Username (optional)", text: $username)
                    }
                    fieldRow(icon: "envelope.fill", placeholder: "Email address", text: $email, isEmail: true)
                    fieldRow(icon: "lock.fill", placeholder: "Password", text: $password, isSecure: true)
                }
                .padding(.horizontal, 24)

                if let error = authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.4))
                        .padding(.horizontal, 24)
                }

                Button {
                    Task {
                        await onSubmit(email, password, name.isEmpty ? nil : name, username.isEmpty ? nil : username)
                    }
                } label: {
                    HStack {
                        if authService.isLoading { ProgressView().tint(.white) }
                        Text(buttonText).font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.0, green: 0.75, blue: 0.85), Color(red: 0.2, green: 0.5, blue: 1.0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .cyan.opacity(0.3), radius: 12, y: 6)
                }
                .disabled(email.isEmpty || password.count < 6 || authService.isLoading)
                .opacity(email.isEmpty || password.count < 6 ? 0.5 : 1)
                .padding(.horizontal, 24)

                if showName {
                    Text("By creating an account, you agree to our Terms of Service")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            Spacer()
            Spacer()
        }
    }

    private func fieldRow(icon: String, placeholder: String, text: Binding<String>, isEmail: Bool = false, isSecure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)

            if isSecure {
                SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.3)))
                    .foregroundStyle(.white)
            } else {
                TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.3)))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(isEmail ? .never : .words)
                    .autocorrectionDisabled()
                    .keyboardType(isEmail ? .emailAddress : .default)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    LoginView(authService: AuthService.shared)
}
