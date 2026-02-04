//
//  EmailVerificationView.swift
//  Resonance
//
//  Created by Copilot on 1/21/26.
//

import SwiftUI

struct EmailVerificationView: View {
    let email: String
    var onGoToSignIn: (() -> Void)? = nil
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    @State private var isResending = false
    @State private var resendMessage: String?
    @State private var canDismiss = false
    
    var body: some View {
        ZStack {
            Color(red: 0.15, green: 0.08, blue: 0.18)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Icon
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white.opacity(0.8))
                
                // Title
                Text("verify your email")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                // Message
                VStack(spacing: 12) {
                    Text("we've sent a verification link to:")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                    
                    Text(email)
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text("click the link in the email to verify your account, then return here to sign in.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                    
                    Text("(check your spam folder if you don't see it)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                
                Spacer()
                
                // Resend button
                Button(action: {
                    Task {
                        isResending = true
                        do {
                            try await authManager.resendVerificationEmail()
                            resendMessage = "verification email sent!"
                        } catch {
                            resendMessage = "Error: \(error.localizedDescription)"
                        }
                        isResending = false
                        
                        // Clear message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            resendMessage = nil
                        }
                    }
                }) {
                    Group {
                        if isResending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("resend verification email")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .disabled(isResending)
                
                if let message = resendMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(message.contains("Error") ? .red : .green)
                }
                
                // Go to Sign In button
                Button(action: {
                    canDismiss = true
                    if let onGoToSignIn = onGoToSignIn {
                        onGoToSignIn()
                    }
                    dismiss()
                }) {
                    Text("go to sign in")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.top, 20)
                
                Spacer()
                    .frame(height: 60)
            }
        }
        .interactiveDismissDisabled(!canDismiss)
    }
}

#Preview {
    EmailVerificationView(email: "test@example.com")
        .environmentObject(AuthenticationManager())
}
