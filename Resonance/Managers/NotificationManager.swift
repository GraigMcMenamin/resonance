//
//  NotificationManager.swift
//  Resonance
//
//  Created by Claude on 2/11/26.
//

import Foundation
import SwiftUI
import Combine
import UserNotifications
import FirebaseMessaging

@MainActor
class NotificationManager: NSObject, ObservableObject {
    @Published var hasPermission = false
    @Published var fcmToken: String?
    @Published var pendingRecommendationsCount: Int = 0
    
    private var firebaseService: FirebaseService?
    private var currentUserId: String?
    
    override init() {
        super.init()
        checkNotificationPermission()
    }
    
    func initialize(firebaseService: FirebaseService) {
        self.firebaseService = firebaseService
    }
    
    // MARK: - Permission Management
    
    func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.hasPermission = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            hasPermission = granted
            
            if granted {
                // Register for remote notifications on main thread
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            
            return granted
        } catch {
            print("Error requesting notification permission: \(error)")
            return false
        }
    }
    
    // MARK: - FCM Token Management
    
    func setUserId(_ userId: String?) {
        self.currentUserId = userId
        
        if let userId = userId, let token = fcmToken {
            // Save existing token to Firestore for current user
            Task {
                await saveFCMToken(userId: userId, token: token)
            }
        }
    }
    
    func handleFCMTokenRefresh(_ token: String) {
        print("📱 FCM Token refreshed: \(token)")
        self.fcmToken = token
        
        // Save to Firestore if we have a user ID
        if let userId = currentUserId {
            Task {
                await saveFCMToken(userId: userId, token: token)
            }
        }
    }
    
    private func saveFCMToken(userId: String, token: String) async {
        guard let firebaseService = firebaseService else {
            print("FirebaseService not initialized")
            return
        }
        
        do {
            try await firebaseService.saveFCMToken(userId: userId, token: token)
            print("FCM token saved to Firestore")
        } catch {
            print("Error saving FCM token: \(error)")
        }
    }
    
    func removeFCMToken() async {
        guard let userId = currentUserId,
              let token = fcmToken,
              let firebaseService = firebaseService else {
            return
        }
        
        do {
            try await firebaseService.removeFCMToken(userId: userId, token: token)
            print("FCM token removed from Firestore")
        } catch {
            print("Error removing FCM token: \(error)")
        }
        
        fcmToken = nil
        currentUserId = nil
    }
    
    // MARK: - Notification Handling
    
    func handleNotification(_ userInfo: [AnyHashable: Any]) {
        print("📬 Received notification: \(userInfo)")
        
        // Extract notification data
        guard let type = userInfo["type"] as? String else {
            print("Notification missing type")
            return
        }
        
        switch type {
        case "recommendation":
            handleRecommendationNotification(userInfo)
        case "rating":
            handleRatingNotification(userInfo)
        case "review":
            handleReviewNotification(userInfo)
        default:
            print("Unknown notification type: \(type)")
        }
    }
    
    private func handleRecommendationNotification(_ userInfo: [AnyHashable: Any]) {
        // Handle song recommendation notification
        // You can navigate to the appropriate view or update UI
        print("Recommendation notification")
    }
    
    private func handleRatingNotification(_ userInfo: [AnyHashable: Any]) {
        // Handle rating notification
        print("Rating notification")
    }
    
    private func handleReviewNotification(_ userInfo: [AnyHashable: Any]) {
        // Handle review notification
        print("Review notification")
    }
    
    // MARK: - Badge Management
    
    /// Update the app badge to show pending recommendations count
    /// Call this when app becomes active or when recommendations change
    func updateBadge(pendingCount: Int) {
        pendingRecommendationsCount = pendingCount
        UNUserNotificationCenter.current().setBadgeCount(pendingCount) { error in
            if let error = error {
                print("Error setting badge count: \(error)")
            } else {
                print("📛 Badge updated to \(pendingCount)")
            }
        }
    }
    
    /// Clear the badge completely
    func clearBadge() {
        updateBadge(pendingCount: 0)
    }
    
    /// Refresh badge count by fetching pending recommendations
    func refreshBadgeCount() async {
        guard let userId = currentUserId,
              let firebaseService = firebaseService else {
            return
        }
        
        do {
            let recommendations = try await firebaseService.getReceivedRecommendations(userId: userId)
            // Get user's ratings to filter out already rated items
            let userRatings = firebaseService.allRatings.filter { $0.userId == userId }
            let ratedSpotifyIds = Set(userRatings.map { $0.spotifyId })
            
            let pendingCount = recommendations.filter { rec in
                rec.status == .pending && !ratedSpotifyIds.contains(rec.spotifyId)
            }.count
            
            updateBadge(pendingCount: pendingCount)
        } catch {
            print("Error refreshing badge count: \(error)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Handle notifications when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo as [AnyHashable: Any]
        
        Task { @MainActor [userInfo] in
            self.handleNotification(userInfo)
        }
        
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo as [AnyHashable: Any]
        
        Task { @MainActor [userInfo] in
            self.handleNotification(userInfo)
        }
        
        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension NotificationManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else { return }
        
        Task { @MainActor in
            self.handleFCMTokenRefresh(fcmToken)
        }
    }
}
