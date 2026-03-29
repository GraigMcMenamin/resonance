//
//  RatingsManager.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import Foundation
import Combine

@MainActor
class RatingsManager: ObservableObject {
    @Published var ratings: [UserRating] = [] // Current user's ratings
    @Published var allRatings: [UserRating] = [] // All users' ratings
    @Published var totalRatingsCount: Int = 0 // True total from Firestore count aggregation
    @Published var isLoading = false
    @Published var hasMoreRatings = false
    @Published var errorMessage: String?
    
    private let firebaseService: FirebaseService
    private var cancellables = Set<AnyCancellable>()
    var currentUserId: String? // Track current user for filtering
    
    init(firebaseService: FirebaseService) {
        self.firebaseService = firebaseService
        print("[RatingsManager] Initializing...")
        setupFirebaseListener()
    }
    
    // MARK: - Setup
    
    private func setupFirebaseListener() {
        print("[RatingsManager] Setting up Firebase listener...")
        
        // Listen to all ratings from Firebase
        firebaseService.$allRatings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] allRatings in
                guard let self = self else { return }
                print("[RatingsManager] Received \(allRatings.count) ratings from FirebaseService")
                self.allRatings = allRatings
            }
            .store(in: &cancellables)
        
        // Start listening
        firebaseService.startListeningToAllRatings()
    }
    
    // MARK: - CRUD Operations
    
    func addOrUpdateRating(_ rating: UserRating) async {
        // Save to Firebase - this will trigger the listener to update local array
        do {
            try await firebaseService.saveRating(rating)
            // Optimistically update local array
            if let index = ratings.firstIndex(where: { $0.id == rating.id }) {
                ratings[index] = rating
            } else {
                ratings.append(rating)
                totalRatingsCount += 1
            }
        } catch {
            errorMessage = "Failed to save rating: \(error.localizedDescription)"
            print("Error saving rating to Firebase: \(error)")
        }
    }
    
    func deleteRating(id: String) async {
        do {
            try await firebaseService.deleteRating(id: id)
            // Optimistically update local array
            let existed = ratings.contains { $0.id == id }
            ratings.removeAll { $0.id == id }
            if existed { totalRatingsCount = max(0, totalRatingsCount - 1) }
        } catch {
            errorMessage = "Failed to delete rating: \(error.localizedDescription)"
            print("Error deleting rating from Firebase: \(error)")
        }
    }
    
    func getRating(for id: String) -> UserRating? {
        ratings.first { $0.id == id } ?? allRatings.first { $0.id == id }
    }
    
    // MARK: - Load User Ratings
    
    func loadUserRatings(userId: String, forceRefresh: Bool = false) async {
        // Skip if already loaded for this user (e.g. navigating away and back)
        guard forceRefresh || currentUserId != userId || ratings.isEmpty else { return }
        isLoading = true
        currentUserId = userId
        // Reset cursor so we start from page 1
        firebaseService.resetUserRatingsPagination(for: userId)
        do {
            async let ratingsTask = firebaseService.fetchNextUserRatingsPage(userId: userId)
            async let countTask = firebaseService.getUserRatingCount(userId: userId)
            let (result, count) = try await (ratingsTask, countTask)
            self.ratings = result.ratings
            self.totalRatingsCount = count
            self.hasMoreRatings = self.ratings.count < count
            isLoading = false
        } catch {
            errorMessage = "Failed to load ratings: \(error.localizedDescription)"
            isLoading = false
        }
    }

    func loadMoreUserRatings(userId: String) async {
        guard hasMoreRatings, !isLoading else { return }
        isLoading = true
        do {
            let result = try await firebaseService.fetchNextUserRatingsPage(userId: userId)
            self.ratings.append(contentsOf: result.ratings)
            self.hasMoreRatings = self.ratings.count < self.totalRatingsCount
            isLoading = false
        } catch {
            errorMessage = "Failed to load more ratings: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    /// Force-refreshes by re-fetching from page 1.
    func refreshUserRatings(userId: String) async {
        await loadUserRatings(userId: userId, forceRefresh: true)
    }
    
    func clearUserRatings() {
        ratings = []
        hasMoreRatings = false
        currentUserId = nil
    }
    
    // MARK: - Filtering
    
    func getRatings(ofType type: UserRating.RatingType) -> [UserRating] {
        ratings.filter { $0.type == type }
            .sorted { $0.dateRated > $1.dateRated }
    }
    
    var allRatingsSorted: [UserRating] {
        ratings.sorted { $0.dateRated > $1.dateRated }
    }
    
    // MARK: - Statistics (Current User)
    
    func averageRating(for type: UserRating.RatingType? = nil) -> Double? {
        let filteredRatings = type.map { getRatings(ofType: $0) } ?? ratings
        guard !filteredRatings.isEmpty else { return nil }
        let sum = filteredRatings.reduce(0) { $0 + $1.percentage }
        return Double(sum) / Double(filteredRatings.count)
    }
    
    // MARK: - Community Statistics
    
    func getAggregatedRatings(type: UserRating.RatingType? = nil, currentUserId: String? = nil) -> [AggregatedRating] {
        return firebaseService.getAggregatedRatings(type: type, currentUserId: currentUserId)
    }
    
    func getAverageRating(for spotifyId: String) -> Double? {
        return firebaseService.getAverageRating(for: spotifyId)
    }
    
    func getRatingCount(for spotifyId: String) -> Int {
        return firebaseService.getRatingCount(for: spotifyId)
    }
    
    func getRatingsForItem(spotifyId: String) -> [UserRating] {
        return allRatings.filter { $0.spotifyId == spotifyId }
    }
    
    func getTopRatedItems(type: UserRating.RatingType, limit: Int = 10) -> [AggregatedRating] {
        return firebaseService.getTopRatedItems(type: type, limit: limit)
    }
    
    // MARK: - Buddy Ratings
    
    /// Get ratings for a specific item from a list of buddy user IDs
    func getBuddyRatings(for spotifyId: String, buddyIds: [String]) -> [UserRating] {
        let buddyIdSet = Set(buddyIds)
        return allRatings.filter { $0.spotifyId == spotifyId && buddyIdSet.contains($0.userId) }
            .sorted { $0.dateRated > $1.dateRated }
    }
    
    // MARK: - Firebase is Source of Truth
    // No local persistence - all data comes from Firebase
    
    deinit {
        // Note: firebaseService.stopListening() should be called before deallocation
        // but we cannot safely call MainActor-isolated methods from deinit in Swift 6
        // The listener will be cleaned up when firebaseService is deallocated
    }
}
