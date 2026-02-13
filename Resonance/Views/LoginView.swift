//
//  LoginView.swift
//  SENTS
//
//  Created by Mcmenamin, Graig on 1/15/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showEmailLogin = false
    @State private var showEmailSignup = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.08, blue: 0.18),
                    Color(red: 0.1, green: 0.05, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // App logo/title
                VStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .cornerRadius(24)
                    
                    Text("resonance")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("see what people think about music")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Login buttons
                VStack(spacing: 16) {
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    } else {
                        // Spotify Login
                        Button(action: {
                            Task {
                                await authManager.loginWithSpotify()
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 20))
                                
                                Text("continue with spotify")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 30)
                                    .fill(Color(red: 0.11, green: 0.73, blue: 0.33))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 40)
                        
                        // OR Divider
                        HStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                            
                            Text("OR")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 12)
                            
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 40)
                        
                        // Email Login
                        Button(action: {
                            showEmailLogin = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 18))
                                
                                Text("sign in with email")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 30)
                                    .fill(Color.white.opacity(0.15))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 40)
                        
                        // Sign Up Link
                        Button(action: {
                            showEmailSignup = true
                        }) {
                            HStack(spacing: 4) {
                                Text("don't have an account?")
                                    .foregroundColor(.white.opacity(0.6))
                                Text("sign up")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            .font(.system(size: 14))
                        }
                        
                        // Guest mode button
                        Button(action: {
                            authManager.continueAsGuest()
                        }) {
                            Text("continue as guest")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.top, 8)
                        }
                        
                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                    }
                }
                
                Spacer()
                    .frame(height: 60)
            }
        }
        .sheet(isPresented: $showEmailLogin) {
            EmailLoginView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showEmailSignup) {
            EmailSignupView {
                // When signup view requests to go to sign in, close signup and open login
                showEmailSignup = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showEmailLogin = true
                }
            }
            .environmentObject(authManager)
        }
    }
}

// MARK: - Email Login View

struct EmailLoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var showForgotPassword = false
    @State private var resetEmail = ""
    @State private var resetMessage: String?
    @State private var isResetting = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("sign in")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.top, 40)
                    
                    // Form
                    VStack(spacing: 16) {
                        // Email
                        VStack(alignment: .leading, spacing: 8) {
                            Text("email")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            
                            TextField("", text: $email)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                        }
                        
                        // Password
                        VStack(alignment: .leading, spacing: 8) {
                            Text("password")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            
                            SecureField("", text: $password)
                                .textContentType(.password)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 30)
                    
                    // Sign In Button
                    Button(action: {
                        Task {
                            await authManager.signInWithEmail(email: email, password: password)
                            if authManager.isAuthenticated {
                                dismiss()
                            }
                        }
                    }) {
                        Group {
                            if authManager.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            } else {
                                Text("sign in")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 30)
                    .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
                    
                    // Forgot Password
                    Button(action: {
                        resetEmail = email
                        showForgotPassword = true
                    }) {
                        Text("forgot password?")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 8)
                    
                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Reset Password", isPresented: $showForgotPassword) {
                TextField("Email", text: $resetEmail)
                    .textContentType(.emailAddress)
                .autocapitalization(.none)
            
            Button("Cancel", role: .cancel) {
                resetMessage = nil
            }
            
            Button("Send Reset Link") {
                Task {
                    isResetting = true
                    do {
                        try await authManager.resetPassword(email: resetEmail)
                        resetMessage = "Password reset email sent! Check your inbox."
                    } catch {
                        resetMessage = "Error: \(error.localizedDescription)"
                    }
                    isResetting = false
                }
            }
            .disabled(resetEmail.isEmpty || isResetting)
        } message: {
            if let message = resetMessage {
                Text(message)
            } else {
                Text("Enter your email address to receive a password reset link.")
            }
        }
        }
    }
}

// MARK: - Email Signup View

struct EmailSignupView: View {
    var onGoToSignIn: (() -> Void)? = nil
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showVerificationReminder = false
    @State private var signupSuccessEmail: String?
    @State private var shouldDismissToSignIn = false
    
    var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }
    
    var isFormValid: Bool {
        !email.isEmpty && passwordsMatch && password.count >= 6
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Text("create account")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(.top, 40)
                        
                        // Form
                        VStack(spacing: 16) {
                            // Email
                            VStack(alignment: .leading, spacing: 8) {
                                Text("email")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                TextField("", text: $email)
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                            }
                            
                            // Password
                            VStack(alignment: .leading, spacing: 8) {
                                Text("password")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                SecureField("", text: $password)
                                    .textContentType(.newPassword)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                
                                if !password.isEmpty && password.count < 6 {
                                    Text("password must be at least 6 characters")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            // Confirm Password
                            VStack(alignment: .leading, spacing: 8) {
                                Text("confirm password")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                SecureField("", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                                
                                if !confirmPassword.isEmpty && !passwordsMatch {
                                    Text("Passwords don't match")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.horizontal, 30)
                        
                        // Sign Up Button
                        Button(action: {
                            Task {
                                await authManager.signUpWithEmail(email: email, password: password)
                                if authManager.errorMessage == nil {
                                    // Signup successful, show verification screen
                                    signupSuccessEmail = email
                                }
                            }
                        }) {
                            Group {
                                if authManager.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                } else {
                                    Text("create account")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isFormValid ? Color.white : Color.gray.opacity(0.3))
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 30)
                        .disabled(!isFormValid || authManager.isLoading)
                        
                        if let error = authManager.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                        }
                        
                        Spacer()
                            .frame(height: 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: Binding(
                get: { signupSuccessEmail != nil },
                set: { if !$0 { signupSuccessEmail = nil } }
            )) {
                if let email = signupSuccessEmail {
                    EmailVerificationView(email: email) {
                        // When user taps "Go to Sign In", dismiss this sheet and trigger parent callback
                        shouldDismissToSignIn = true
                    }
                    .environmentObject(authManager)
                    .interactiveDismissDisabled()
                }
            }
            .onChange(of: shouldDismissToSignIn) { _, newValue in
                if newValue {
                    dismiss()
                    onGoToSignIn?()
                }
            }
        }
    }
    
    
    #Preview {
        LoginView()
            .environmentObject(AuthenticationManager())
    }
}
