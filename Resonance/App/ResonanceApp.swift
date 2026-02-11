//
//  ResonanceApp.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import SwiftUI
import UIKit
import FirebaseMessaging
import UserNotifications

@main
struct ResonanceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var firebaseService = FirebaseService()
    @StateObject private var spotifyService = SpotifyService()
    @StateObject private var buddyManager = BuddyManager()
    @StateObject private var notificationManager = NotificationManager()
    
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
                .environmentObject(notificationManager)
                .onAppear {
                    setupNotifications()
                }
        }
    }
    
    private func setupNotifications() {
        // Initialize notification manager with firebase service
        notificationManager.initialize(firebaseService: firebaseService)
        
        // Set delegates for FCM and notifications
        Messaging.messaging().delegate = notificationManager
        UNUserNotificationCenter.current().delegate = notificationManager
        
        // Register for remote notifications
        Task {
            let granted = await notificationManager.requestPermission()
            if granted {
                print("✅ Notification permission granted")
            } else {
                print("⚠️ Notification permission denied")
            }
        }
    }
}
