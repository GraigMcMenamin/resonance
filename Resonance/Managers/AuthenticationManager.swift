//
//  AuthenticationManager.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/15/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine
import AuthenticationServices
import UIKit

@MainActor
class AuthenticationManager: NSObject, ObservableObject {
    @Published var currentUser: AppUser?
    @Published var isAuthenticated = false
    @Published var isGuestMode = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var spotifyAuthSession: ASWebAuthenticationSession?
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    override init() {
        super.init()
        setupAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    // MARK: - Auth State Listener
    
    private func setupAuthStateListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let user = user {
                    // Load user profile
                    let profile = await self.loadUserProfile(firebaseUID: user.uid)
                    
                    if let profile = profile {
                        // For email users, check if email is verified
                        // For Spotify users, skip email verification check
                        if profile.authMethod == .emailPassword && !user.isEmailVerified {
                            print("Email not verified, not auto-logging in")
                            try? Auth.auth().signOut()
                            self.currentUser = nil
                            self.isAuthenticated = false
                        } else {
                            // User is authenticated
                            self.isAuthenticated = true
                            print("Auto-login successful")
                        }
                    } else {
                        // No profile found - might be a new user or deleted profile
                        self.isAuthenticated = false
                    }
                } else {
                    self.currentUser = nil
                    self.isAuthenticated = false
                    // Don't reset guest mode here
                }
            }
        }
    }
    
    // MARK: - Guest Mode
    
    func continueAsGuest() {
        isGuestMode = true
        isAuthenticated = false
        currentUser = nil
        errorMessage = nil
    }
    
    func exitGuestMode() {
        isGuestMode = false
    }
    
    // MARK: - Spotify OAuth Login
    
    func loginWithSpotify() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Step 1: Get Spotify authorization code
            print("[AuthenticationManager] Step 1: Getting Spotify auth code...")
            let authCode = try await getSpotifyAuthCode()
            print("[AuthenticationManager] Got auth code")
            
            // Step 2: Exchange auth code for access token
            print("[AuthenticationManager] Step 2: Exchanging code for tokens...")
            let tokens = try await exchangeCodeForTokens(authCode: authCode)
            print("[AuthenticationManager] Got tokens")
            
            // Step 3: Get Spotify user profile
            print("[AuthenticationManager] Step 3: Fetching Spotify profile...")
            let spotifyProfile = try await getSpotifyUserProfile(accessToken: tokens.accessToken)
            print("[AuthenticationManager] Got profile: \(spotifyProfile.displayName)")
            
            // Step 4: Sign into Firebase with custom token or anonymous auth
            print("[AuthenticationManager] Step 4: Signing into Firebase...")
            try await signIntoFirebase(spotifyUserId: spotifyProfile.id, spotifyAccessToken: tokens.accessToken)
            print("[AuthenticationManager] Signed into Firebase")
            
            // Step 5: Check if user needs to set username
            print("[AuthenticationManager] Step 5: Checking for username...")
            let existingUser = try? await loadUserProfile(firebaseUID: Auth.auth().currentUser?.uid ?? "")
            
            let user: AppUser
            if let existingUser = existingUser, existingUser.username != nil {
                // User already has username, load their full profile
                user = existingUser
            } else {
                // New user or existing user without username - create temporary user
                user = AppUser(
                    id: spotifyProfile.id,
                    firebaseUID: Auth.auth().currentUser?.uid ?? "",
                    username: nil,
                    usernameLowercase: nil,
                    spotifyId: spotifyProfile.id,
                    spotifyAccessToken: tokens.accessToken,
                    spotifyRefreshToken: tokens.refreshToken,
                    tokenExpirationDate: Date().addingTimeInterval(TimeInterval(tokens.expiresIn)),
                    email: spotifyProfile.email,
                    imageURL: spotifyProfile.images?.first?.url,
                    authMethod: .spotify
                )
                
                // Save basic profile (will be updated with username later)
                await saveUserProfile(user: user)
                print("[AuthenticationManager] User needs to set username")
            }
            
            self.currentUser = user
            self.isAuthenticated = true
            self.isLoading = false
            print("[AuthenticationManager] Login complete!")
        } catch {
            print("[AuthenticationManager] Login failed: \(error)")
            self.errorMessage = "Login failed: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
    
    // MARK: - Email/Password Authentication
    
    func signUpWithEmail(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Step 1: Create Firebase Auth user
            print("[AuthenticationManager] Creating email/password user...")
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            print("[AuthenticationManager] Created user with UID: \(result.user.uid)")
            
            // Send verification email
            do {
                try await result.user.sendEmailVerification()
                print("[AuthenticationManager] Verification email sent to \(email)")
            } catch {
                print("[AuthenticationManager] Failed to send verification email: \(error.localizedDescription)")
                // Continue anyway - don't block signup if email fails
            }
            
            // Step 2: Create user profile (without username yet)
            let user = AppUser(
                id: result.user.uid,
                firebaseUID: result.user.uid,
                username: nil,
                usernameLowercase: nil,
                spotifyId: nil,
                spotifyAccessToken: nil,
                spotifyRefreshToken: nil,
                tokenExpirationDate: nil,
                email: email,
                imageURL: nil,
                authMethod: .emailPassword
            )
            
            await saveUserProfile(user: user)
            print("[AuthenticationManager] User profile saved")
            
            // Don't authenticate yet - they need to verify email first
            self.currentUser = nil
            self.isAuthenticated = false
            self.isLoading = false
            print("[AuthenticationManager] Waiting for email verification")
        } catch {
            print("[AuthenticationManager] Signup failed: \(error)")
            self.errorMessage = "Signup failed: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
    
    func signInWithEmail(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Sign in with Firebase Auth
            print("[AuthenticationManager] Signing in with email/password...")
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            print("[AuthenticationManager] Signed in with UID: \(result.user.uid)")
            
            // Check if email is verified
            if !result.user.isEmailVerified {
                try await Auth.auth().signOut()
                self.currentUser = nil
                self.isAuthenticated = false
                self.isLoading = false
                self.errorMessage = "Please verify your email address before signing in. Check your inbox for the verification link."
                print("[AuthenticationManager] Email not verified, blocking access")
                return
            }
            
            // Load user profile
            _ = await loadUserProfile(firebaseUID: result.user.uid)
            
            self.isAuthenticated = true
            self.isLoading = false
            print("[AuthenticationManager] Login complete!")
        } catch {
            print("[AuthenticationManager] Login failed: \(error)")
            self.errorMessage = "Login failed: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
    
    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
        print("[AuthenticationManager] Password reset email sent to \(email)")
    }
    
    func resendVerificationEmail() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.noUser
        }
        
        try await user.sendEmailVerification()
        print("[AuthenticationManager] Verification email resent")
    }
    
    // MARK: - Username Management
    
    func checkUsernameAvailability(_ username: String) async throws -> Bool {
        let db = Firestore.firestore()
        let lowercaseUsername = username.lowercased()
        
        // Query for any user with this lowercase username
        let snapshot = try await db.collection("users")
            .whereField("usernameLowercase", isEqualTo: lowercaseUsername)
            .getDocuments()
        
        return snapshot.documents.isEmpty
    }
    
    func setUsername(_ username: String) async throws {
        guard var user = currentUser else {
            throw AuthError.noUser
        }
        
        // Double-check availability
        let available = try await checkUsernameAvailability(username)
        guard available else {
            throw AuthError.usernameNotAvailable
        }
        
        // Update user with username
        user.username = username
        user.usernameLowercase = username.lowercased()
        
        // Save to Firestore
        await saveUserProfile(user: user)
        
        // Update local state
        self.currentUser = user
        print("[AuthenticationManager] Username set: @\(username)")
    }
    
    // MARK: - User Profile Management
    
    private func loadUserProfile(firebaseUID: String) async -> AppUser? {
        let db = Firestore.firestore()
        
        do {
            let document = try await db.collection("users").document(firebaseUID).getDocument()
            
            guard let data = document.data() else {
                print("[AuthenticationManager] No user profile found for UID: \(firebaseUID)")
                return nil
            }
            
            let user = try Firestore.Decoder().decode(AppUser.self, from: data)
            self.currentUser = user
            print("[AuthenticationManager] Loaded user profile: @\(user.username ?? user.id)")
            return user
        } catch {
            print("[AuthenticationManager] Error loading user profile: \(error)")
            return nil
        }
    }
    private func getSpotifyAuthCode() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let scopes = ["user-read-email", "user-read-private"]
            let scopeString = scopes.joined(separator: "%20")
            
            guard let encodedRedirectURI = SpotifyConfig.redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                continuation.resume(throwing: AuthError.invalidURL)
                return
            }
            
            let authURLString = """
            https://accounts.spotify.com/authorize?\
            client_id=\(SpotifyConfig.clientId)&\
            response_type=code&\
            redirect_uri=\(encodedRedirectURI)&\
            scope=\(scopeString)&\
            show_dialog=true
            """
            
            guard let authURL = URL(string: authURLString) else {
                continuation.resume(throwing: AuthError.invalidURL)
                return
            }
            
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "resonance"
            ) { callbackURL, error in
                if let error = error {
                    print("[AuthenticationManager] Auth session error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    print("[AuthenticationManager] No callback URL received")
                    continuation.resume(throwing: AuthError.noAuthCode)
                    return
                }
                
                print("[AuthenticationManager] Callback URL: \(callbackURL.absoluteString)")
                
                guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
                    print("[AuthenticationManager] Failed to parse callback URL")
                    continuation.resume(throwing: AuthError.noAuthCode)
                    return
                }
                
                // Check for error in callback
                if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
                    print("[AuthenticationManager] Spotify returned error: \(error)")
                    continuation.resume(throwing: AuthError.spotifyAuthError(error))
                    return
                }
                
                guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    print("[AuthenticationManager] No auth code in callback URL")
                    print("[AuthenticationManager] Query items: \(components.queryItems ?? [])")
                    continuation.resume(throwing: AuthError.noAuthCode)
                    return
                }
                
                print("[AuthenticationManager] Got auth code: \(code.prefix(10))...")
                continuation.resume(returning: code)
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            
            DispatchQueue.main.async {
                self.spotifyAuthSession = session
                session.start()
            }
        }
    }
    
    private func exchangeCodeForTokens(authCode: String) async throws -> SpotifyTokenResponse {
        guard let url = URL(string: "\(SpotifyConfig.cloudFunctionBaseURL)/exchangeSpotifyCode") else {
            throw AuthError.tokenExchangeFailed
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "code": authCode,
            "redirectUri": SpotifyConfig.redirectURI
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("[AuthenticationManager] Exchanging code for tokens via Cloud Function...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("[AuthenticationManager] No HTTP response")
            throw AuthError.tokenExchangeFailed
        }
        
        print("[AuthenticationManager] Response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("[AuthenticationManager] Token exchange failed: \(responseString)")
            }
            throw AuthError.tokenExchangeFailed
        }
        
        do {
            let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            print("[AuthenticationManager] Successfully decoded token response")
            return tokenResponse
        } catch {
            print("[AuthenticationManager] Failed to decode token response: \(error)")
            throw error
        }
    }
    
    private func getSpotifyUserProfile(accessToken: String) async throws -> SpotifyUserProfile {
        let profileURL = URL(string: "https://api.spotify.com/v1/me")!
        
        var request = URLRequest(url: profileURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.profileFetchFailed
        }
        
        return try JSONDecoder().decode(SpotifyUserProfile.self, from: data)
    }
    
    private func signIntoFirebase(spotifyUserId: String, spotifyAccessToken: String) async throws {
        // Call Cloud Function to get custom Firebase token
        let firebaseToken = try await getFirebaseCustomToken(spotifyAccessToken: spotifyAccessToken)
        
        // Sign in to Firebase with custom token
        let result = try await Auth.auth().signIn(withCustomToken: firebaseToken)
        print("[AuthenticationManager] Signed into Firebase with custom token: \(result.user.uid)")
        print("[AuthenticationManager]    Firebase UID will always be: \(spotifyUserId)")
    }
    
    private func getFirebaseCustomToken(spotifyAccessToken: String) async throws -> String {
        // TODO: Replace with your deployed Cloud Function URL
        // After deploying: firebase deploy --only functions
        // You'll get a URL like: https://us-central1-resonance-6e5b1.cloudfunctions.net/authenticateWithSpotify
        let functionURL = URL(string: "https://us-central1-resonance-6e5b1.cloudfunctions.net/authenticateWithSpotify")!
        
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["spotifyAccessToken": spotifyAccessToken]
        request.httpBody = try JSONEncoder().encode(body)
        
        print("[AuthenticationManager] Requesting custom Firebase token from backend...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.backendError("No HTTP response")
        }
        
        print("[AuthenticationManager] Backend response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[AuthenticationManager] Backend error: \(errorMessage)")
            throw AuthError.backendError(errorMessage)
        }
        
        let tokenResponse = try JSONDecoder().decode(FirebaseTokenResponse.self, from: data)
        print("[AuthenticationManager] Got Firebase custom token from backend")
        
        return tokenResponse.firebaseToken
    }
    
    private func saveUserProfile(user: AppUser) async {
        let db = Firestore.firestore()
        do {
            try db.collection("users").document(user.firebaseUID).setData(from: user)
            print("[AuthenticationManager] Saved user profile for: @\(user.username ?? user.id)")
        } catch {
            print("[AuthenticationManager] Error saving user profile: \(error)")
        }
    }
    
    // MARK: - Logout
    
    func logout() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            errorMessage = "Logout failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Token Refresh
    
    func refreshSpotifyTokenIfNeeded() async {
        guard let user = currentUser,
              let refreshToken = user.spotifyRefreshToken,
              let expirationDate = user.tokenExpirationDate,
              Date() > expirationDate.addingTimeInterval(-300) else { // Refresh 5 min before expiry
            return
        }
        
        do {
            let tokens = try await refreshSpotifyToken(refreshToken: refreshToken)
            
            var updatedUser = user
            updatedUser.spotifyAccessToken = tokens.accessToken
            updatedUser.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
            if let newRefreshToken = tokens.refreshToken {
                updatedUser.spotifyRefreshToken = newRefreshToken
            }
            
            await saveUserProfile(user: updatedUser)
            self.currentUser = updatedUser
        } catch {
            print("Failed to refresh token: \(error)")
        }
    }
    
    private func refreshSpotifyToken(refreshToken: String) async throws -> SpotifyTokenResponse {
        guard let url = URL(string: "\(SpotifyConfig.cloudFunctionBaseURL)/refreshSpotifyToken") else {
            throw AuthError.tokenRefreshFailed
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["refreshToken": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.tokenRefreshFailed
        }
        
        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AuthenticationManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windowScene = UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            
            guard let window = windowScene?.windows.first else {
                fatalError("No window scene available")
            }
            return window
        }
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidURL
    case noAuthCode
    case tokenExchangeFailed
    case profileFetchFailed
    case tokenRefreshFailed
    case spotifyAuthError(String)
    case noAccessToken
    case backendError(String)
    case noUser
    case usernameNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noAuthCode:
            return "No authorization code received"
        case .tokenExchangeFailed:
            return "Failed to exchange code for token"
        case .profileFetchFailed:
            return "Failed to fetch user profile"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .spotifyAuthError(let error):
            return "Spotify auth error: \(error)"
        case .noAccessToken:
            return "No Spotify access token available"
        case .backendError(let error):
            return "Backend error: \(error)"
        case .noUser:
            return "No user logged in"
        case .usernameNotAvailable:
            return "Username is already taken"
        }
    }
}

// MARK: - Response Models

struct FirebaseTokenResponse: Codable {
    let firebaseToken: String
    let user: BackendUserInfo
}

struct BackendUserInfo: Codable {
    let id: String
    let displayName: String
    let email: String?
    let imageURL: String?
}
