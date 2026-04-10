import AuthenticationServices
import SwiftUI

/// Login screen with Apple Sign-In and Google Sign-In options.
/// Requirements: 11.1, 11.2, 11.3
struct LoginView: View {

    @ObservedObject var authService: AuthService

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.03, green: 0.03, blue: 0.10)
                .ignoresSafeArea()

            // Subtle radial glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.orange.opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 600)
                .offset(y: -100)

            VStack(spacing: 0) {
                Spacer()

                // App branding
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 120, height: 120)
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.orange, .orange.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .accessibilityHidden(true)
                    }

                    Text("Orbi")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Your next adventure starts here")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()
                Spacer()

                // Sign-in buttons
                VStack(spacing: 14) {
                    // Apple Sign-In (Req 11.1)
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task {
                            await authService.handleAppleSignIn(result: result)
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Sign in with Apple")

                    // Google Sign-In placeholder (Req 11.2)
                    Button {
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                            Text("Sign in with Google")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white)
                        .foregroundStyle(.black.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel("Sign in with Google")

                    // Error message
                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    #if DEBUG
                    Button {
                        authService.isAuthenticated = true
                        authService.userId = "debug-user"
                    } label: {
                        Text("Skip Login (Debug)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.top, 8)
                    }
                    #endif
                }
                .padding(.horizontal, 28)
                .disabled(authService.isLoading)
                .overlay {
                    if authService.isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                }

                Spacer()
                    .frame(height: 56)
            }
        }
    }
}

#Preview {
    LoginView(authService: AuthService.shared)
}
