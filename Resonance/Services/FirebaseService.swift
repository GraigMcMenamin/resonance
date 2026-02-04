//
//  FirebaseService.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/15/26.
//

import Foundation
import FirebaseFirestore
import Combine

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

@MainActor
class FirebaseService: ObservableObject {
    private let db = Firestore.firestore()
    
    @Published var allRatings: [UserRating] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var ratingsListener: ListenerRegistration?
    
    nonisolated init() {}
    
    // MARK: - Real-time Listeners
    
    func startListeningToAllRatings() {
        ratingsListener?.remove()
        
        print("🔥 [FirebaseService] Starting ratings listener...")
        
        ratingsListener = db.collection("ratings")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ [FirebaseService] Error listening to ratings: \(error.localizedDescription)")
                    Task { @MainActor in
                        self.errorMessage = "Failed to fetch ratings: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("⚠️ [FirebaseService] No documents in snapshot")
                    return
                }
                
                print("📊 [FirebaseService] Received \(documents.count) rating documents from Firestore")
                
                Task { @MainActor in
                    self.allRatings = documents.compactMap { doc in
                        try? doc.data(as: UserRating.self)
                    }
                    print("✅ [FirebaseService] Parsed \(self.allRatings.count) ratings successfully")
                    print("📋 [FirebaseService] Sample ratings: \(self.allRatings.prefix(3).map { $0.name })")
                }
            }
    }
    
    func stopListening() {
        ratingsListener?.remove()
        ratingsListener = nil
    }
    
    // MARK: - Rating CRUD Operations
    
    func saveRating(_ rating: UserRating) async throws {
        try db.collection("ratings")
            .document(rating.id)
            .setData(from: rating)
    }
    
    func deleteRating(id: String) async throws {
        try await db.collection("ratings")
            .document(id)
            .delete()
    }
    
    func getRating(id: String) async throws -> UserRating? {
        let document = try await db.collection("ratings")
            .document(id)
            .getDocument()
        
        return try? document.data(as: UserRating.self)
    }
    
    // MARK: - Fetch Ratings by Criteria
    
    func fetchUserRatings(userId: String) async throws -> [UserRating] {
        let snapshot = try await db.collection("ratings")
            .whereField("userId", isEqualTo: userId)
            .order(by: "dateRated", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: UserRating.self)
        }
    }
    
    func fetchRatingsForItem(spotifyId: String) async throws -> [UserRating] {
        let snapshot = try await db.collection("ratings")
            .whereField("spotifyId", isEqualTo: spotifyId)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: UserRating.self)
        }
    }
    
    func fetchRatingsByType(_ type: UserRating.RatingType) async throws -> [UserRating] {
        let snapshot = try await db.collection("ratings")
            .whereField("type", isEqualTo: type.rawValue)
            .order(by: "dateRated", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: UserRating.self)
        }
    }
    
    // MARK: - Aggregated Ratings
    
    func getAggregatedRatings(type: UserRating.RatingType? = nil, currentUserId: String? = nil) -> [AggregatedRating] {
        var ratings = allRatings
        
        // Filter by type if specified
        if let type = type {
            ratings = ratings.filter { $0.type == type }
        }
        
        // Group by Spotify ID
        let grouped = Dictionary(grouping: ratings) { $0.spotifyId }
        
        // Create aggregated ratings
        return grouped.compactMap { spotifyId, userRatings in
            guard let first = userRatings.first else { return nil }
            
            let total = userRatings.reduce(0) { $0 + $1.percentage }
            let average = Double(total) / Double(userRatings.count)
            let currentUserRating = userRatings.first { $0.userId == currentUserId }
            
            return AggregatedRating(
                id: spotifyId,
                type: first.type,
                name: first.name,
                artistName: first.artistName,
                imageURL: first.imageURL,
                averagePercentage: average,
                totalRatings: userRatings.count,
                userRatings: userRatings,
                currentUserRating: currentUserRating
            )
        }
        .sorted { $0.averagePercentage > $1.averagePercentage }
    }
    
    func getAverageRating(for spotifyId: String) -> Double? {
        let itemRatings = allRatings.filter { $0.spotifyId == spotifyId }
        guard !itemRatings.isEmpty else { return nil }
        
        let total = itemRatings.reduce(0) { $0 + $1.percentage }
        return Double(total) / Double(itemRatings.count)
    }
    
    func getRatingCount(for spotifyId: String) -> Int {
        return allRatings.filter { $0.spotifyId == spotifyId }.count
    }
    
    // MARK: - User Profile Operations
    
    func saveUserProfile(_ user: AppUser) async throws {
        try db.collection("users")
            .document(user.id)
            .setData(from: user)
    }
    
    func getUserProfile(userId: String) async throws -> AppUser? {
        let document = try await db.collection("users")
            .document(userId)
            .getDocument()
        
        return try? document.data(as: AppUser.self)
    }
    
    func getAllUsers() async throws -> [AppUser] {
        let snapshot = try await db.collection("users")
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: AppUser.self)
        }
    }
    
    // MARK: - Statistics
    
    func getTopRatedItems(type: UserRating.RatingType, limit: Int = 10) -> [AggregatedRating] {
        let aggregated = getAggregatedRatings(type: type)
        return Array(aggregated.prefix(limit))
    }
    
    func getMostActiveUsers(limit: Int = 10) -> [(userId: String, userName: String?, ratingCount: Int)] {
        let grouped = Dictionary(grouping: allRatings) { $0.userId }
        
        return grouped.map { userId, ratings in
            let userName = ratings.first?.userName
            return (userId: userId, userName: userName, ratingCount: ratings.count)
        }
        .sorted { $0.ratingCount > $1.ratingCount }
        .prefix(limit)
        .map { $0 }
    }
    
    // MARK: - Top Items Operations
    
    func saveUserTopItems(userId: String, topArtists: [TopItem], topTracks: [TopItem], topAlbums: [TopItem]) async throws {
        let topItems = UserTopItems(
            id: userId,
            userId: userId,
            topArtists: topArtists,
            topTracks: topTracks,
            topAlbums: topAlbums
        )
        
        try db.collection("userTopItems")
            .document(userId)
            .setData(from: topItems)
    }
    
    func getUserTopItems(userId: String) async throws -> UserTopItems? {
        let document = try await db.collection("userTopItems")
            .document(userId)
            .getDocument()
        
        return try? document.data(as: UserTopItems.self)
    }
    
    func deleteUserTopItems(userId: String) async throws {
        try await db.collection("userTopItems")
            .document(userId)
            .delete()
    }
    
    // MARK: - User Search Operations
    
    func searchUsers(query: String, limit: Int = 20) async throws -> [AppUser] {
        guard !query.isEmpty else { return [] }
        
        let lowercaseQuery = query.lowercased()
        
        // Search by username prefix (case-insensitive using lowercase field)
        let snapshot = try await db.collection("users")
            .whereField("usernameLowercase", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("usernameLowercase", isLessThan: lowercaseQuery + "\u{f8ff}")
            .limit(to: limit)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: AppUser.self)
        }
    }
    
    func getUserRatings(userId: String) async throws -> [UserRating] {
        let snapshot = try await db.collection("ratings")
            .whereField("userId", isEqualTo: userId)
            .order(by: "dateRated", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: UserRating.self)
        }
    }
    
    // MARK: - Buddy Request Operations
    
    func sendBuddyRequest(from fromUser: AppUser, to toUser: AppUser) async throws {
        let requestId = BuddyRequest.makeId(fromUserId: fromUser.id, toUserId: toUser.id)
        
        let request = BuddyRequest(
            id: requestId,
            fromUserId: fromUser.id,
            toUserId: toUser.id,
            fromUsername: fromUser.username ?? fromUser.displayName,
            fromDisplayName: fromUser.displayName,
            fromImageURL: fromUser.imageURL,
            toUsername: toUser.username,
            toDisplayName: toUser.displayName,
            toImageURL: toUser.imageURL,
            status: .pending,
            createdAt: Date()
        )
        
        try db.collection("buddyRequests")
            .document(requestId)
            .setData(from: request)
    }
    
    func getPendingBuddyRequests(forUserId userId: String) async throws -> [BuddyRequest] {
        let snapshot = try await db.collection("buddyRequests")
            .whereField("toUserId", isEqualTo: userId)
            .whereField("status", isEqualTo: BuddyRequest.BuddyRequestStatus.pending.rawValue)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: BuddyRequest.self)
        }
    }
    
    func getSentBuddyRequests(fromUserId userId: String) async throws -> [BuddyRequest] {
        let snapshot = try await db.collection("buddyRequests")
            .whereField("fromUserId", isEqualTo: userId)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: BuddyRequest.self)
        }
    }
    
    func acceptBuddyRequest(_ request: BuddyRequest) async throws {
        // Update request status to accepted
        try await db.collection("buddyRequests")
            .document(request.id)
            .updateData(["status": BuddyRequest.BuddyRequestStatus.accepted.rawValue])
        
        // Add buddy to both users' buddy lists
        let now = Date()
        
        // Add to sender's buddies (the receiver becomes sender's buddy)
        let buddy1 = Buddy(
            id: request.toUserId,
            oderId: request.toUserId,
            username: request.toUsername,
            displayName: request.toDisplayName,
            imageURL: request.toImageURL,
            buddySince: now
        )
        try db.collection("users")
            .document(request.fromUserId)
            .collection("buddies")
            .document(request.toUserId)
            .setData(from: buddy1)
        
        // Add to receiver's buddies
        let buddy2 = Buddy(
            id: request.fromUserId,
            oderId: request.fromUserId,
            username: request.fromUsername,
            displayName: request.fromDisplayName,
            imageURL: request.fromImageURL,
            buddySince: now
        )
        try db.collection("users")
            .document(request.toUserId)
            .collection("buddies")
            .document(request.fromUserId)
            .setData(from: buddy2)
    }
    
    func rejectBuddyRequest(_ request: BuddyRequest) async throws {
        try await db.collection("buddyRequests")
            .document(request.id)
            .updateData(["status": BuddyRequest.BuddyRequestStatus.rejected.rawValue])
    }
    
    func deleteBuddyRequest(requestId: String) async throws {
        try await db.collection("buddyRequests")
            .document(requestId)
            .delete()
    }
    
    func getBuddies(forUserId userId: String) async throws -> [Buddy] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("buddies")
            .order(by: "buddySince", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: Buddy.self)
        }
    }
    
    func removeBuddy(userId: String, buddyId: String) async throws {
        // Remove from both users' buddy lists
        try await db.collection("users")
            .document(userId)
            .collection("buddies")
            .document(buddyId)
            .delete()
        
        try await db.collection("users")
            .document(buddyId)
            .collection("buddies")
            .document(userId)
            .delete()
    }
    
    func checkBuddyStatus(userId: String, otherUserId: String) async throws -> BuddyStatus {
        // Check if already buddies
        let buddyDoc = try await db.collection("users")
            .document(userId)
            .collection("buddies")
            .document(otherUserId)
            .getDocument()
        
        if buddyDoc.exists {
            return .buddies
        }
        
        // Check if there's a pending request from current user
        let sentRequestId = BuddyRequest.makeId(fromUserId: userId, toUserId: otherUserId)
        let sentRequestDoc = try await db.collection("buddyRequests")
            .document(sentRequestId)
            .getDocument()
        
        if let sentRequest = try? sentRequestDoc.data(as: BuddyRequest.self) {
            if sentRequest.status == .pending {
                return .requestSent
            }
        }
        
        // Check if there's a pending request from other user
        let receivedRequestId = BuddyRequest.makeId(fromUserId: otherUserId, toUserId: userId)
        let receivedRequestDoc = try await db.collection("buddyRequests")
            .document(receivedRequestId)
            .getDocument()
        
        if let receivedRequest = try? receivedRequestDoc.data(as: BuddyRequest.self) {
            if receivedRequest.status == .pending {
                return .requestReceived
            }
        }
        
        return .notBuddies
    }
    
    enum BuddyStatus {
        case notBuddies
        case requestSent
        case requestReceived
        case buddies
    }
    
    // MARK: - Review CRUD Operations
    
    func saveReview(_ review: Review) async throws {
        try db.collection("reviews")
            .document(review.id)
            .setData(from: review)
    }
    
    func deleteReview(id: String) async throws {
        try await db.collection("reviews")
            .document(id)
            .delete()
    }
    
    func getReview(id: String) async throws -> Review? {
        let document = try await db.collection("reviews")
            .document(id)
            .getDocument()
        
        return try? document.data(as: Review.self)
    }
    
    func getUserReview(userId: String, spotifyId: String) async throws -> Review? {
        let reviewId = Review.makeId(userId: userId, spotifyId: spotifyId)
        return try await getReview(id: reviewId)
    }
    
    // MARK: - Fetch Reviews by Criteria
    
    func fetchUserReviews(userId: String) async throws -> [Review] {
        let snapshot = try await db.collection("reviews")
            .whereField("userId", isEqualTo: userId)
            .order(by: "dateCreated", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: Review.self)
        }
    }
    
    func fetchBuddyReviews(buddyIds: [String]) async throws -> [Review] {
        guard !buddyIds.isEmpty else { return [] }
        
        // Firestore 'in' queries are limited to 10 items, so we need to batch
        var allReviews: [Review] = []
        let chunks = buddyIds.chunked(into: 10)
        
        for chunk in chunks {
            let snapshot = try await db.collection("reviews")
                .whereField("userId", in: chunk)
                .order(by: "dateCreated", descending: true)
                .getDocuments()
            
            let reviews = snapshot.documents.compactMap { doc in
                try? doc.data(as: Review.self)
            }
            allReviews.append(contentsOf: reviews)
        }
        
        // Sort all reviews by date
        return allReviews.sorted { $0.dateCreated > $1.dateCreated }
    }
    
    /// Fetch reviews for an item from the ratings collection (new consolidated model)
    /// This fetches ratings that have reviewContent and converts them to Review objects
    func fetchReviewsFromRatings(spotifyId: String) async throws -> [Review] {
        let snapshot = try await db.collection("ratings")
            .whereField("spotifyId", isEqualTo: spotifyId)
            .order(by: "dateRated", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> Review? in
            guard let rating = try? doc.data(as: UserRating.self),
                  rating.hasReviewContent else { return nil }
            return rating.toReview()
        }
    }
    
    /// Fetch all reviews for an item from both ratings and legacy reviews collections
    func fetchAllReviewsForItem(spotifyId: String) async throws -> [Review] {
        // Fetch from new ratings collection
        let ratingsReviews = try await fetchReviewsFromRatings(spotifyId: spotifyId)
        
        // Also fetch from legacy reviews collection for backwards compatibility
        let legacyReviews = try await fetchReviewsForItem(spotifyId: spotifyId)
        
        // Merge and deduplicate by ID (ratings take precedence as they're newer)
        var reviewsById: [String: Review] = [:]
        
        // Add legacy reviews first
        for review in legacyReviews {
            reviewsById[review.id] = review
        }
        
        // Override with ratings-based reviews (newer data)
        for review in ratingsReviews {
            reviewsById[review.id] = review
        }
        
        // Sort by date created descending
        return Array(reviewsById.values).sorted { $0.dateCreated > $1.dateCreated }
    }
    
    func fetchReviewsForItem(spotifyId: String) async throws -> [Review] {
        let snapshot = try await db.collection("reviews")
            .whereField("spotifyId", isEqualTo: spotifyId)
            .order(by: "dateCreated", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: Review.self)
        }
    }
    
    func fetchReviewsForItem(spotifyId: String, reviewLength: Review.ReviewLength) async throws -> [Review] {
        let snapshot = try await db.collection("reviews")
            .whereField("spotifyId", isEqualTo: spotifyId)
            .whereField("reviewLength", isEqualTo: reviewLength.rawValue)
            .order(by: "dateCreated", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: Review.self)
        }
    }
    
    func getReviewCount(for spotifyId: String) async throws -> Int {
        let snapshot = try await db.collection("reviews")
            .whereField("spotifyId", isEqualTo: spotifyId)
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    // MARK: - Review Like Operations (stored under ratings collection)
    
    func likeReview(reviewId: String, user: AppUser) async throws {
        let likeId = ReviewLike.makeId(reviewId: reviewId, userId: user.id)
        let like = ReviewLike(
            id: likeId,
            reviewId: reviewId,
            userId: user.id,
            username: user.username,
            userDisplayName: user.displayName,
            userImageURL: user.imageURL,
            createdAt: Date()
        )
        
        try db.collection("ratings")
            .document(reviewId)
            .collection("likes")
            .document(likeId)
            .setData(from: like)
    }
    
    func unlikeReview(reviewId: String, userId: String) async throws {
        let likeId = ReviewLike.makeId(reviewId: reviewId, userId: userId)
        try await db.collection("ratings")
            .document(reviewId)
            .collection("likes")
            .document(likeId)
            .delete()
    }
    
    func hasUserLikedReview(reviewId: String, userId: String) async throws -> Bool {
        let likeId = ReviewLike.makeId(reviewId: reviewId, userId: userId)
        let document = try await db.collection("ratings")
            .document(reviewId)
            .collection("likes")
            .document(likeId)
            .getDocument()
        
        return document.exists
    }
    
    func getReviewLikesCount(reviewId: String) async throws -> Int {
        let snapshot = try await db.collection("ratings")
            .document(reviewId)
            .collection("likes")
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    func getReviewLikes(reviewId: String) async throws -> [ReviewLike] {
        let snapshot = try await db.collection("ratings")
            .document(reviewId)
            .collection("likes")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: ReviewLike.self)
        }
    }
    
    // MARK: - Review Comment Operations (stored under ratings collection)
    
    func addComment(to reviewId: String, content: String, user: AppUser) async throws -> ReviewComment {
        let commentId = UUID().uuidString
        let comment = ReviewComment(
            id: commentId,
            reviewId: reviewId,
            userId: user.id,
            username: user.username,
            userDisplayName: user.displayName,
            userImageURL: user.imageURL,
            content: content,
            createdAt: Date()
        )
        
        try db.collection("ratings")
            .document(reviewId)
            .collection("comments")
            .document(commentId)
            .setData(from: comment)
        
        return comment
    }
    
    func deleteComment(reviewId: String, commentId: String) async throws {
        try await db.collection("ratings")
            .document(reviewId)
            .collection("comments")
            .document(commentId)
            .delete()
    }
    
    func getReviewComments(reviewId: String) async throws -> [ReviewComment] {
        let snapshot = try await db.collection("ratings")
            .document(reviewId)
            .collection("comments")
            .order(by: "createdAt", descending: false)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: ReviewComment.self)
        }
    }
    
    func getReviewCommentsCount(reviewId: String) async throws -> Int {
        let snapshot = try await db.collection("ratings")
            .document(reviewId)
            .collection("comments")
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    // MARK: - Comment Like Operations (stored under ratings collection)
    
    func likeComment(reviewId: String, commentId: String, user: AppUser) async throws {
        let likeId = CommentLike.makeId(commentId: commentId, userId: user.id)
        let like = CommentLike(
            id: likeId,
            reviewId: reviewId,
            commentId: commentId,
            userId: user.id,
            username: user.username,
            userDisplayName: user.displayName,
            createdAt: Date()
        )
        
        try db.collection("ratings")
            .document(reviewId)
            .collection("comments")
            .document(commentId)
            .collection("likes")
            .document(likeId)
            .setData(from: like)
    }
    
    func unlikeComment(reviewId: String, commentId: String, userId: String) async throws {
        let likeId = CommentLike.makeId(commentId: commentId, userId: userId)
        try await db.collection("ratings")
            .document(reviewId)
            .collection("comments")
            .document(commentId)
            .collection("likes")
            .document(likeId)
            .delete()
    }
    
    func hasUserLikedComment(reviewId: String, commentId: String, userId: String) async throws -> Bool {
        let likeId = CommentLike.makeId(commentId: commentId, userId: userId)
        let document = try await db.collection("ratings")
            .document(reviewId)
            .collection("comments")
            .document(commentId)
            .collection("likes")
            .document(likeId)
            .getDocument()
        
        return document.exists
    }
    
    func getCommentLikesCount(reviewId: String, commentId: String) async throws -> Int {
        let snapshot = try await db.collection("ratings")
            .document(reviewId)
            .collection("comments")
            .document(commentId)
            .collection("likes")
            .getDocuments()
        
        return snapshot.documents.count
    }
}
