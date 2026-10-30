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
    /// Music the user sent that the receiver hasn't reviewed or ignored yet
    @Published var sentRecommendations: [MusicRecommendation] = []
    @Published var notifications: [AppNotification] = []

    // Recommendations load in two passes: items newer than `recentCutoff` first, then older ones
    @Published private(set) var isLoadingRecentRecommendations = false
    @Published private(set) var isLoadingOlderRecommendations = false
    @Published private(set) var isLoadingRecentSent = false
    @Published private(set) var isLoadingOlderSent = false
    @Published private(set) var isLoadingNotifications = false

    var isLoadingRecommendations: Bool { isLoadingRecentRecommendations || isLoadingOlderRecommendations }
    var isLoadingSent: Bool { isLoadingRecentSent || isLoadingOlderSent }
    var isLoading: Bool { isLoadingRecommendations || isLoadingSent || isLoadingNotifications }

    /// Recommendations sent after this date load first; the mailbox also hides older ones behind "see more"
    static var recentCutoff: Date {
        Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? .distantPast
    }

    private var firebaseService: FirebaseService?
    private var currentUserId: String?
    // Bumped on every refresh so a superseded refresh can't overwrite newer results
    private var refreshGeneration = 0

    /// Total count of items needing the user's attention (badge for the mailbox tab)
    var unreadCount: Int {
        pendingRecommendations.count + notifications.filter { !$0.read }.count
    }

    func initialize(firebaseService: FirebaseService) {
        self.firebaseService = firebaseService
    }

    func setUserId(_ userId: String?) {
        let userChanged = userId != currentUserId
        currentUserId = userId
        if let userId = userId {
            // MailboxView calls this on every appear; don't restart a load that's already running
            guard userChanged || !isLoading else { return }
            Task { await refresh(userId: userId) }
        } else {
            refreshGeneration += 1
            pendingRecommendations = []
            sentRecommendations = []
            notifications = []
            isLoadingRecentRecommendations = false
            isLoadingOlderRecommendations = false
            isLoadingRecentSent = false
            isLoadingOlderSent = false
            isLoadingNotifications = false
        }
    }

    func refresh() async {
        guard let userId = currentUserId else { return }
        await refresh(userId: userId)
    }

    private func refresh(userId: String) async {
        guard let firebaseService = firebaseService else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let cutoff = Self.recentCutoff

        isLoadingRecentRecommendations = true
        isLoadingOlderRecommendations = true
        isLoadingRecentSent = true
        isLoadingOlderSent = true
        isLoadingNotifications = true

        // Each stream publishes as soon as it's ready so the fastest content shows first
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadNotifications(userId: userId, firebaseService: firebaseService, generation: generation) }
            group.addTask { await self.loadReceived(userId: userId, firebaseService: firebaseService, generation: generation, cutoff: cutoff) }
            group.addTask { await self.loadSent(userId: userId, firebaseService: firebaseService, generation: generation, cutoff: cutoff) }
        }
    }

    private func loadNotifications(userId: String, firebaseService: FirebaseService, generation: Int) async {
        do {
            let fetched = try await firebaseService.getNotifications(userId: userId)
            guard generation == refreshGeneration else { return }
            notifications = fetched
        } catch {
            print("[MailboxManager] Error loading notifications: \(error)")
        }
        guard generation == refreshGeneration else { return }
        isLoadingNotifications = false
    }

    private func loadReceived(userId: String, firebaseService: FirebaseService, generation: Int, cutoff: Date) async {
        do {
            let recent = try await firebaseService.getReceivedRecommendations(userId: userId, sentOnOrAfter: cutoff)
            let recentPending = await pendingAndUnrated(recent, firebaseService: firebaseService)
            guard generation == refreshGeneration else { return }
            pendingRecommendations = recentPending + pendingRecommendations.filter { $0.sentAt < cutoff }
            isLoadingRecentRecommendations = false

            let older = try await firebaseService.getReceivedRecommendations(userId: userId, sentBefore: cutoff)
            let olderPending = await pendingAndUnrated(older, firebaseService: firebaseService)
            guard generation == refreshGeneration else { return }
            pendingRecommendations = pendingRecommendations.filter { $0.sentAt >= cutoff } + olderPending
        } catch {
            print("[MailboxManager] Error loading recommendations: \(error)")
        }
        guard generation == refreshGeneration else { return }
        isLoadingRecentRecommendations = false
        isLoadingOlderRecommendations = false
    }

    private func loadSent(userId: String, firebaseService: FirebaseService, generation: Int, cutoff: Date) async {
        do {
            let recent = try await firebaseService.getSentRecommendations(userId: userId, sentOnOrAfter: cutoff)
            let recentPending = await pendingAndUnrated(recent, firebaseService: firebaseService)
            guard generation == refreshGeneration else { return }
            sentRecommendations = recentPending + sentRecommendations.filter { $0.sentAt < cutoff }
            isLoadingRecentSent = false

            let older = try await firebaseService.getSentRecommendations(userId: userId, sentBefore: cutoff)
            let olderPending = await pendingAndUnrated(older, firebaseService: firebaseService)
            guard generation == refreshGeneration else { return }
            sentRecommendations = sentRecommendations.filter { $0.sentAt >= cutoff } + olderPending
        } catch {
            print("[MailboxManager] Error loading sent recommendations: \(error)")
        }
        guard generation == refreshGeneration else { return }
        isLoadingRecentSent = false
        isLoadingOlderSent = false
    }

    /// Still-pending recommendations whose receiver hasn't rated the item; items are checked with concurrent queries
    private func pendingAndUnrated(_ recs: [MusicRecommendation], firebaseService: FirebaseService) async -> [MusicRecommendation] {
        let pending = recs.filter { $0.status == .pending }

        let ratedPairs = await withTaskGroup(of: [String].self) { group -> Set<String> in
            for (spotifyId, itemRecs) in Dictionary(grouping: pending, by: { $0.spotifyId }) {
                let receiverIds = Array(Set(itemRecs.map { $0.receiverId }))
                group.addTask {
                    // On failure keep the items listed rather than hiding them
                    let ratings = (try? await firebaseService.fetchRatingsForItemByUsers(spotifyId: spotifyId, userIds: receiverIds)) ?? []
                    return ratings.map { "\($0.userId)|\($0.spotifyId)" }
                }
            }

            var pairs = Set<String>()
            for await found in group {
                pairs.formUnion(found)
            }
            return pairs
        }

        return pending.filter { !ratedPairs.contains("\($0.receiverId)|\($0.spotifyId)") }
    }


    /// Pokes the receiver to listen; limited to once per 24 hours per recommendation
    @discardableResult
    func poke(_ recommendation: MusicRecommendation) async -> Bool {
        guard let firebaseService = firebaseService, recommendation.canPoke else { return false }
        do {
            try await firebaseService.pokeRecommendation(id: recommendation.id)
            if let index = sentRecommendations.firstIndex(where: { $0.id == recommendation.id }) {
                sentRecommendations[index].lastPokedAt = Date()
            }
            return true
        } catch {
            print("[MailboxManager] Error poking recommendation: \(error)")
            return false
        }
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
