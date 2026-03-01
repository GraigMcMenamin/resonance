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

// MARK: - Deep Link Model

enum NotificationDeepLink: Equatable {
    /// Navigate to buddy ratings tab, optionally scroll to a specific feed item
    case buddyRatingFeed(scrollToId: String?)
    /// Navigate to ReviewsListView for a specific item
    case reviewsList(spotifyId: String, itemName: String, artistName: String?, imageURL: String?, itemType: String, scrollToReviewId: String?)
    /// Navigate to home page (for recommendation notifications)
    case homePage
}

@MainActor
class NotificationManager: NSObject, ObservableObject {
    @Published var hasPermission = false
    @Published var fcmToken: String?
    @Published var pendingRecommendationsCount: Int = 0
    @Published var pendingDeepLink: NotificationDeepLink?
    
    private var firebaseService: FirebaseService?
    private var buddyManager: BuddyManager?
    private var currentUserId: String?
    
    override init() {
        super.init()
        checkNotificationPermission()
    }
    
    func initialize(firebaseService: FirebaseService) {
        self.firebaseService = firebaseService
    }
    
    func setBuddyManager(_ buddyManager: BuddyManager) {
        self.buddyManager = buddyManager
        
        // Check for cold-start notification that AppDelegate captured
        if let pendingUserInfo = AppDelegate.pendingNotificationUserInfo {
            AppDelegate.pendingNotificationUserInfo = nil
            print("📬 Processing cold-start notification: \(pendingUserInfo)")
            handleNotificationTap(pendingUserInfo)
        }
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
    
    /// Called when a notification is received (foreground) - just log it
    func handleNotification(_ userInfo: [AnyHashable: Any]) {
        print("📬 Received notification: \(userInfo)")
    }
    
    /// Called when user taps a notification - set deep link for navigation
    func handleNotificationTap(_ userInfo: [AnyHashable: Any]) {
        print("📬 User tapped notification: \(userInfo)")
        
        guard let type = userInfo["type"] as? String else {
            print("Notification missing type")
            return
        }
        
        switch type {
        case "recommendation":
            handleRecommendationTap(userInfo)
        case "rating", "review":
            handleBuddyRatingTap(userInfo)
        case "like":
            handleLikeTap(userInfo)
        case "comment":
            handleCommentTap(userInfo)
        default:
            print("Unknown notification type: \(type)")
        }
    }
    
    // MARK: - Tap Handlers
    
    private func handleRecommendationTap(_ userInfo: [AnyHashable: Any]) {
        // Music sent to you → open on home page
        pendingDeepLink = .homePage
    }
    
    private func handleBuddyRatingTap(_ userInfo: [AnyHashable: Any]) {
        let ratingId = userInfo["ratingId"] as? String
        let scrollId = ratingId.map { "rating_\($0)" }
        pendingDeepLink = .buddyRatingFeed(scrollToId: scrollId)
    }
    
    private func handleLikeTap(_ userInfo: [AnyHashable: Any]) {
        let likerId = userInfo["likerId"] as? String ?? ""
        let hasReview = userInfo["hasReviewContent"] as? String == "true"
        let isBuddy = buddyManager?.buddies.contains(where: { $0.id == likerId }) ?? false
        
        if hasReview && !isBuddy {
            // Written review liked by non-buddy → reviews list page
            setReviewsListDeepLink(from: userInfo)
        } else {
            // Buddy liked (written or not), or non-buddy liked percentage-only → buddy ratings page, scroll to it
            let ratingId = userInfo["ratingId"] as? String
            let scrollId = ratingId.map { "rating_\($0)" }
            pendingDeepLink = .buddyRatingFeed(scrollToId: scrollId)
        }
    }
    
    private func handleCommentTap(_ userInfo: [AnyHashable: Any]) {
        let commenterId = userInfo["commenterId"] as? String ?? ""
        let hasReview = userInfo["hasReviewContent"] as? String == "true"
        let isBuddy = buddyManager?.buddies.contains(where: { $0.id == commenterId }) ?? false
        
        if hasReview {
            // Written review commented on (by buddy or non-buddy) → reviews list page
            setReviewsListDeepLink(from: userInfo)
        } else {
            // Percentage-only rating commented on → buddy ratings page, scroll to it
            let ratingId = userInfo["ratingId"] as? String
            let scrollId = ratingId.map { "rating_\($0)" }
            pendingDeepLink = .buddyRatingFeed(scrollToId: scrollId)
        }
    }
    
    private func setReviewsListDeepLink(from userInfo: [AnyHashable: Any]) {
        let spotifyId = userInfo["spotifyId"] as? String ?? ""
        let itemName = userInfo["itemName"] as? String ?? "Unknown"
        let artistName = userInfo["artistName"] as? String
        let imageURL = userInfo["imageURL"] as? String
        let itemType = userInfo["itemType"] as? String ?? "track"
        let ratingId = userInfo["ratingId"] as? String
        
        pendingDeepLink = .reviewsList(
            spotifyId: spotifyId,
            itemName: itemName,
            artistName: artistName,
            imageURL: imageURL,
            itemType: itemType,
            scrollToReviewId: ratingId
        )
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
    
    // Handle notification tap - set deep link for navigation
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo as [AnyHashable: Any]
        
        Task { @MainActor [userInfo] in
            self.handleNotificationTap(userInfo)
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
