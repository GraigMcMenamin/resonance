//
//  ContentView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var spotifyService: SpotifyService
    
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.15, green: 0.08, blue: 0.18, alpha: 1.0)
        
        // Unselected tab items - white
        appearance.stackedLayoutAppearance.normal.iconColor = .white
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white]
        
        // Selected tab items - brighter white
        appearance.stackedLayoutAppearance.selected.iconColor = .white
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        
        // Set navigation bar appearance
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(red: 0.15, green: 0.08, blue: 0.18, alpha: 1.0)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }
    
    var body: some View {
        Group {
            if authManager.isGuestMode {
                // Guest mode - full access without saving
                AuthenticatedView(firebaseService: firebaseService)
            } else if authManager.isAuthenticated {
                // Check if user has username
                if authManager.currentUser?.username != nil {
                    // Full access
                    AuthenticatedView(firebaseService: firebaseService)
                } else {
                    // Need to set username first
                    UsernameSetupView()
                }
            } else {
                // Not authenticated - show login
                LoginView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Authenticated View

struct AuthenticatedView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @StateObject private var ratingsManager: RatingsManager
    
    init(firebaseService: FirebaseService) {
        _ratingsManager = StateObject(wrappedValue: RatingsManager(firebaseService: firebaseService))
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color(red: 0.15, green: 0.08, blue: 0.18)
                .ignoresSafeArea()
            
            TabView {
                HomeView()
                    .tabItem {
                        Label("home", systemImage: "house.fill")
                    }
                
                SearchView()
                    .tabItem {
                        Label("search", systemImage: "magnifyingglass")
                    }
                
                LibraryView()
                    .tabItem {
                        Label("me & buddies", systemImage: "music.note.list")
                    }
                
                ProfileView()
                    .tabItem {
                        Label("profile", systemImage: "person.fill")
                    }
            }
            .environmentObject(ratingsManager)
        }
        .task {
            // Load user ratings when authenticated (not in guest mode)
            // Spotify ID = Firebase UID via custom token
            if !authManager.isGuestMode, let userId = authManager.currentUser?.id {
                await ratingsManager.loadUserRatings(userId: userId)
            } else if authManager.isGuestMode {
                // Clear ratings in guest mode
                ratingsManager.clearUserRatings()
            }
        }
        .onChange(of: authManager.currentUser?.id) { oldValue, newValue in
            Task {
                if let newUserId = newValue, !authManager.isGuestMode {
                    // User changed, load their ratings
                    await ratingsManager.loadUserRatings(userId: newUserId)
                } else {
                    // User logged out or switched to guest
                    ratingsManager.clearUserRatings()
                }
            }
        }
        .onChange(of: authManager.isGuestMode) { oldValue, newValue in
            if newValue {
                // Switched to guest mode, clear ratings
                ratingsManager.clearUserRatings()
            } else if let userId = authManager.currentUser?.id {
                // Switched from guest to authenticated, load ratings
                Task {
                    await ratingsManager.loadUserRatings(userId: userId)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
