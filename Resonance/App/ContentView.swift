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
    @EnvironmentObject var notificationManager: NotificationManager
    
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
        
        // Make tabs equal width
        UITabBar.appearance().itemPositioning = .fill
        
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
        .onChange(of: authManager.currentUser?.id) { newValue in
            // Update notification manager with user ID
            notificationManager.setUserId(newValue)
        }
        .onAppear {
            // Set initial user ID
            notificationManager.setUserId(authManager.currentUser?.id)
        }
    }
}

// MARK: - Authenticated View

struct AuthenticatedView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var notificationManager: NotificationManager
    @StateObject private var ratingsManager: RatingsManager
    @State private var selectedTab: Int = 0
    
    init(firebaseService: FirebaseService) {
        _ratingsManager = StateObject(wrappedValue: RatingsManager(firebaseService: firebaseService))
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color(red: 0.15, green: 0.08, blue: 0.18)
                .ignoresSafeArea()
            
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("home", systemImage: "house.fill")
                    }
                    .tag(0)
                
                BuddyBoardView()
                    .tabItem {
                        Label("buddies & me", systemImage: "music.note.list")
                    }
                    .tag(1)
                
                SearchView()
                    .tabItem {
                        Label("search", systemImage: "magnifyingglass")
                    }
                    .tag(2)
                
                ProfileView()
                    .tabItem {
                        Label("profile", systemImage: "person.fill")
                    }
                    .tag(3)
            }
            .environmentObject(ratingsManager)
        }
        .onChange(of: notificationManager.pendingDeepLink) { deepLink in
            guard let deepLink = deepLink else { return }
            applyDeepLink(deepLink)
        }
        .onAppear {
            // Handle deep link that was set before this view appeared (cold-start tap)
            if let deepLink = notificationManager.pendingDeepLink {
                // Small delay to ensure the tab view is fully ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    applyDeepLink(deepLink)
                }
            }
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
        .onChange(of: authManager.currentUser?.id) { newValue in
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
        .onChange(of: authManager.isGuestMode) { newValue in
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
    
    private func applyDeepLink(_ deepLink: NotificationDeepLink) {
        switch deepLink {
        case .homePage:
            selectedTab = 0
            notificationManager.pendingDeepLink = nil
        case .buddyRatingFeed, .reviewsList:
            // Switch to the BuddyBoard tab; BuddyBoardView handles scroll/navigation and clears the link itself
            selectedTab = 1
        case .profilePage:
            selectedTab = 3
            notificationManager.pendingDeepLink = nil
        }
    }
}

#Preview {
    ContentView()
}
