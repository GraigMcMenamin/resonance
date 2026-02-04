//
//  UsernameSetupView.swift
//  Resonance
//
//  Created by Copilot on 1/21/26.
//

import SwiftUI

struct UsernameSetupView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var username: String = ""
    @State private var isChecking = false
    @State private var isAvailable: Bool? = nil
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    
    var body: some View {
        ZStack {
            Color(red: 0.15, green: 0.08, blue: 0.18)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 70))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("Choose Your Username")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("This is how other users will find you")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                
                // Username Input
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("@")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.5))
                        
                        TextField("username", text: $username)
                            .font(.title2)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: username) { oldValue, newValue in
                                // Filter to alphanumeric only
                                let filtered = newValue.filter { $0.isLetter || $0.isNumber }
                                if filtered != newValue {
                                    username = filtered
                                }
                                // Limit to 25 characters
                                if username.count > 25 {
                                    username = String(username.prefix(25))
                                }
                                // Reset availability when typing
                                isAvailable = nil
                                errorMessage = nil
                            }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Validation feedback
                    if let errorMessage = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    } else if isChecking {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Checking availability...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    } else if let isAvailable = isAvailable {
                        HStack(spacing: 6) {
                            Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(isAvailable ? .green : .red)
                            Text(isAvailable ? "Username available!" : "Username already taken")
                                .font(.caption)
                                .foregroundColor(isAvailable ? .green : .red)
                        }
                    }
                    
                    // Requirements
                    VStack(alignment: .leading, spacing: 4) {
                        RequirementRow(
                            text: "3-25 characters",
                            isMet: username.count >= 3 && username.count <= 25
                        )
                        RequirementRow(
                            text: "Letters and numbers only",
                            isMet: !username.isEmpty && username.allSatisfy { $0.isLetter || $0.isNumber }
                        )
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 30)
                
                // Check Availability Button
                if username.count >= 3 && isAvailable == nil && !isChecking {
                    Button(action: {
                        Task {
                            await checkUsernameAvailability()
                        }
                    }) {
                        Text("Check Availability")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 30)
                }
                
                // Continue Button
                Button(action: {
                    Task {
                        await submitUsername()
                    }
                }) {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        } else {
                            Text("Continue")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isUsernameValid ? Color.white : Color.gray.opacity(0.3))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 30)
                .disabled(!isUsernameValid || isSubmitting)
                
                Spacer()
            }
        }
    }
    
    private var isUsernameValid: Bool {
        guard username.count >= 3 && username.count <= 25 else { return false }
        guard username.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        guard isAvailable == true else { return false }
        return true
    }
    
    private func checkUsernameAvailability() async {
        isChecking = true
        errorMessage = nil
        
        do {
            let available = try await authManager.checkUsernameAvailability(username)
            isAvailable = available
            if !available {
                errorMessage = "Username already taken"
            }
        } catch {
            errorMessage = "Error checking username: \(error.localizedDescription)"
        }
        
        isChecking = false
    }
    
    private func submitUsername() async {
        guard isUsernameValid else { return }
        
        isSubmitting = true
        
        do {
            try await authManager.setUsername(username)
            // Auth manager will update currentUser and trigger navigation
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }
}

struct RequirementRow: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(isMet ? .green : .white.opacity(0.3))
            
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

#Preview {
    UsernameSetupView()
        .environmentObject(AuthenticationManager())
}
