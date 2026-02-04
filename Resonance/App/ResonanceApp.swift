//
//  ResonanceApp.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import SwiftUI

@main
struct ResonanceApp: App {
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var firebaseService = FirebaseService()
    @StateObject private var spotifyService = SpotifyService()
    @StateObject private var buddyManager = BuddyManager()
    
    init() {
        // Configure Firebase on app launch
        FirebaseConfig.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(firebaseService)
                .environmentObject(spotifyService)
                .environmentObject(buddyManager)
        }
    }
}
