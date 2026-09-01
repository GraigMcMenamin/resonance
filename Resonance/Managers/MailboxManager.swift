//
//  MailboxManager.swift
//  Resonance
//
//  Created by Claude on 2/11/26.
//

import SwiftUI
import Combine

@MainActor
class MailboxManager: ObservableObject {
    @Published var pendingRecommendations: [MusicRecommendation] = []
    @Published var notifications: [AppNotification] = []
    @Published var isLoading = false

    private var firebaseService: FirebaseService?
    private var currentUserId: String?

    /// Total count of items needing the user's attention (badge for the mailbox tab)
    var unreadCount: Int {
        pendingRecommendations.count + notifications.filter { !$0.read }.count
    }

    func initialize(firebaseService: FirebaseService) {
        self.firebaseService = firebaseService
    }

    func setUserId(_ userId: String?) {
        currentUserId = userId
        if let userId = userId {
            Task { await refresh(userId: userId) }
        } else {
            pendingRecommendations = []
            notifications = []
        }
    }

    func refresh() async {
        guard let userId = currentUserId else { return }
        await refresh(userId: userId)
    }

    private func refresh(userId: String) async {
        guard let firebaseService = firebaseService else { return }
        isLoading = true

        do {
            async let recsTask = firebaseService.getReceivedRecommendations(userId: userId)
            async let myRatingsTask = firebaseService.getUserRatings(userId: userId)
            async let notificationsTask = firebaseService.getNotifications(userId: userId)

            let (allRecs, myRatings, fetchedNotifications) = try await (recsTask, myRatingsTask, notificationsTask)
            let ratedSpotifyIds = Set(myRatings.map { $0.spotifyId })

            pendingRecommendations = allRecs.filter { rec in
                rec.status == .pending && !ratedSpotifyIds.contains(rec.spotifyId)
            }
            notifications = fetchedNotifications
        } catch {
            print("[MailboxManager] Error loading mailbox: \(error)")
        }

        isLoading = false
    }

    func ignoreRecommendation(_ recommendation: MusicRecommendation) async {
        guard let firebaseService = firebaseService else { return }
        do {
            try await firebaseService.updateRecommendationStatus(
                recommendationId: recommendation.id,
                status: .ignored,
                ratingId: nil
            )
            pendingRecommendations.removeAll { $0.id == recommendation.id }
        } catch {
            print("[MailboxManager] Error ignoring recommendation: \(error)")
        }
    }

    /// Call after a recommended item has been rated so it no longer shows as pending
    func removePendingRecommendation(spotifyId: String) {
        pendingRecommendations.removeAll { $0.spotifyId == spotifyId }
    }

    func markNotificationRead(_ notification: AppNotification) async {
        guard let firebaseService = firebaseService, let userId = currentUserId, !notification.read else { return }

        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].read = true
        }

        do {
            try await firebaseService.markNotificationRead(userId: userId, notificationId: notification.id)
        } catch {
            print("[MailboxManager] Error marking notification read: \(error)")
        }
    }

    func deleteNotification(_ notification: AppNotification) async {
        guard let firebaseService = firebaseService, let userId = currentUserId else { return }

        notifications.removeAll { $0.id == notification.id }

        do {
            try await firebaseService.deleteNotification(userId: userId, notificationId: notification.id)
        } catch {
            print("[MailboxManager] Error deleting notification: \(error)")
        }
    }
}
