//
//  RatingBadge.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/15/26.
//

import SwiftUI

// Helper function to get color based on percentage
func colorForPercentage(_ percentage: Double) -> Color {
    if percentage >= 80 {
        return Color.green
    } else if percentage >= 60 {
        return Color(red: 0.6, green: 0.8, blue: 0.2) // Yellow-green
    } else if percentage >= 40 {
        return Color.yellow
    } else if percentage >= 20 {
        return Color.orange
    } else {
        return Color.red
    }
}

/// A view that displays rating information with optional average rating
struct RatingBadge: View {
    let spotifyId: String
    @ObservedObject var ratingsManager: RatingsManager
    let userId: String?
    
    private var userRating: UserRating? {
        guard let userId = userId else { return nil }
        let ratingId = UserRating.makeId(userId: userId, spotifyId: spotifyId)
        return ratingsManager.getRating(for: ratingId)
    }
    
    private var averageRating: Double? {
        ratingsManager.getAverageRating(for: spotifyId)
    }
    
    private var ratingCount: Int {
        ratingsManager.getRatingCount(for: spotifyId)
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Average rating (if exists) - shown first and bigger
            if let average = averageRating, ratingCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("\(Int(average))%")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("(\(ratingCount))")
                        .font(.caption2)
                }
                .foregroundColor(colorForPercentage(average))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(colorForPercentage(average).opacity(0.2))
                .cornerRadius(6)
            }
            
            // User's rating (if exists)
            if let rating = userRating {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                    Text("\(rating.percentage)%")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(colorForPercentage(Double(rating.percentage)))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(colorForPercentage(Double(rating.percentage)).opacity(0.15))
                .cornerRadius(6)
            }
        }
    }
}

/// Compact version for list items — fixed-width columns with a divider line
struct RatingBadgeCompact: View {
    let spotifyId: String
    @ObservedObject var ratingsManager: RatingsManager
    let userId: String?
    /// When provided, used instead of querying ratingsManager (avoids global state mutation).
    var averageRatingOverride: Double? = nil
    
    private var userRating: UserRating? {
        guard let userId = userId else { return nil }
        let ratingId = UserRating.makeId(userId: userId, spotifyId: spotifyId)
        return ratingsManager.getRating(for: ratingId)
    }
    
    private var averageRating: Double? {
        averageRatingOverride ?? ratingsManager.getAverageRating(for: spotifyId)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // User rating column
            Text(userRating.map { "\($0.percentage)" } ?? "")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 50, alignment: .center)
            
            // Column divider
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1)
            
            // Average rating column
            Text(averageRating.map { "\(Int($0))" } ?? "")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 55, alignment: .center)
        }
    }
}

// Mini rating bar for compact badge
struct RatingBarMini: View {
    let percentage: Double
    
    private var color: Color {
        colorForPercentage(percentage)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.15))
                
                // Filled portion
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geometry.size.width * (percentage / 100))
            }
        }
    }
}

// MARK: - Buddy Ratings Section

/// A section that displays buddy ratings for a specific item
struct BuddyRatingsSection: View {
    let buddyRatings: [UserRating]
    let buddies: [Buddy]
    var userRating: UserRating? = nil
    // Music item info needed to navigate to the review list
    var spotifyId: String = ""
    var itemName: String = ""
    var artistName: String? = nil
    var imageURL: URL? = nil
    var reviewType: Review.ReviewType = .track
    @State private var showAllRatings = false
    
    /// Whether there's anything to show (user's own rating or buddy ratings)
    private var hasAnyRatings: Bool {
        userRating != nil || !buddyRatings.isEmpty
    }
    
    /// Buddy ratings with the current user's own entry removed to prevent duplicates
    private var filteredBuddyRatings: [UserRating] {
        guard let currentUserId = userRating?.userId else { return buddyRatings }
        return buddyRatings.filter { $0.userId != currentUserId }
    }
    
    private var displayedRatings: [UserRating] {
        if showAllRatings || filteredBuddyRatings.count <= 5 {
            return filteredBuddyRatings
        } else {
            return Array(filteredBuddyRatings.prefix(5))
        }
    }
    
    /// Find buddy info for a given userId
    private func buddyInfo(for userId: String) -> Buddy? {
        return buddies.first { $0.id == userId }
    }
    
    private func reviewNavDestination(reviewId: String, reviewLength: Review.ReviewLength) -> ReviewsListView {
        ReviewsListView(
            spotifyId: spotifyId,
            itemName: itemName,
            artistName: artistName,
            imageURL: imageURL,
            reviewType: reviewType,
            scrollToReviewId: reviewId,
            initialSelectedLength: reviewLength
        )
    }
    
    var body: some View {
        if hasAnyRatings {
            VStack(alignment: .leading, spacing: 12) {
                Text("ratings")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.6))
                    .textCase(.lowercase)
                
                VStack(spacing: 8) {
                    // User's own rating first
                    if let userRating = userRating {
                        BuddyRatingRow(
                            rating: userRating,
                            username: userRating.username,
                            imageURL: userRating.userImageURL,
                            isCurrentUser: true,
                            profileDestination: AnyView(ProfileView(isEmbedded: true)),
                            reviewDestination: userRating.hasReviewContent
                                ? AnyView(reviewNavDestination(reviewId: userRating.id, reviewLength: userRating.reviewLength ?? .short))
                                : nil
                        )
                    }
                    
                    ForEach(displayedRatings) { rating in
                        let buddy = buddyInfo(for: rating.userId)
                        BuddyRatingRow(
                            rating: rating,
                            username: buddy?.username ?? rating.username,
                            imageURL: buddy?.imageURL ?? rating.userImageURL,
                            isCurrentUser: false,
                            profileDestination: AnyView(BuddyProfileDestination(userId: rating.userId)),
                            reviewDestination: rating.hasReviewContent
                                ? AnyView(reviewNavDestination(reviewId: rating.id, reviewLength: rating.reviewLength ?? .short))
                                : nil
                        )
                    }
                    
                    // See More / See Less button
                    if filteredBuddyRatings.count > 5 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllRatings.toggle()
                            }
                        }) {
                            HStack {
                                Text(showAllRatings ? "see less" : "see more (\(filteredBuddyRatings.count - 5) more)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Image(systemName: showAllRatings ? "chevron.up" : "chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

/// Destination view that fetches user data and shows their profile
struct BuddyProfileDestination: View {
    let userId: String
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @State private var user: AppUser?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            // Own profile: resolve synchronously so no state flip occurs during push animation
            if authManager.currentUser?.id == userId {
                ProfileView(isEmbedded: true)
            } else if isLoading {
                ZStack {
                    Color(red: 0.15, green: 0.08, blue: 0.18)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            } else if let user = user {
                OtherUserProfileView(user: user)
            } else {
                ZStack {
                    Color(red: 0.15, green: 0.08, blue: 0.18)
                        .ignoresSafeArea()
                    Text("User not found")
                        .foregroundColor(.white)
                }
            }
        }
        .task {
            guard authManager.currentUser?.id != userId else { return }
            do {
                user = try await firebaseService.getUserProfile(userId: userId)
            } catch {
                print("Error fetching user: \(error)")
            }
            isLoading = false
        }
    }
}

/// A single row displaying a buddy's rating with split-tap navigation.
/// Tapping the profile area navigates to the user's profile.
/// Tapping the review text (if present) navigates to the review list scrolled to that review.
struct BuddyRatingRow: View {
    let rating: UserRating
    let username: String?
    let imageURL: String?
    var isCurrentUser: Bool = false
    /// When provided, the profile header section becomes a NavigationLink to this destination.
    var profileDestination: AnyView? = nil
    /// When provided, the review text section becomes a NavigationLink to this destination.
    var reviewDestination: AnyView? = nil
    @EnvironmentObject var notificationManager: NotificationManager
    
    private var ratingColor: Color {
        colorForPercentage(Double(rating.percentage))
    }
    
    private var profileImageURL: URL? {
        guard let urlString = imageURL else { return nil }
        return URL(string: urlString)
    }
    
    /// Display name: prefer username
    private var displayUsername: String {
        if let username = username, !username.isEmpty {
            return "@\(username)"
        } else if isCurrentUser {
            return "you"
        } else {
            return "User"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Profile section — tappable when profileDestination is provided
            if isCurrentUser {
                Button(action: { notificationManager.pendingDeepLink = .profilePage }) {
                    profileHeaderContent
                }
                .buttonStyle(.plain)
            } else if let profileDest = profileDestination {
                NavigationLink(destination: profileDest) {
                    profileHeaderContent
                }
                .buttonStyle(.plain)
            } else {
                profileHeaderContent
            }
            
            // Review section — show for both short and long reviews
            if rating.hasReviewContent, let reviewContent = rating.reviewContent {
                if let reviewDest = reviewDestination {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 12)
                    NavigationLink(destination: reviewDest) {
                        reviewTextContent(reviewContent)
                    }
                    .buttonStyle(.plain)
                } else {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 12)
                    reviewTextContent(reviewContent)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private var profileHeaderContent: some View {
        HStack(spacing: 12) {
            // Profile picture
            if let imageURL = profileImageURL {
                CustomAsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    default:
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                }
            } else {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }
            
            // Username
            Text(displayUsername)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            // Rating with bar
            HStack(spacing: 8) {
                Text("\(rating.percentage)%")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(ratingColor)
                
                RatingBarMini(percentage: Double(rating.percentage))
                    .frame(width: 50, height: 6)
            }
            
            // Chevron to indicate tappable profile area
            if isCurrentUser || profileDestination != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private func reviewTextContent(_ content: String) -> some View {
        HStack(spacing: 6) {
            Text(content)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
            Spacer()
            // Small indicator that review text is tappable
            if reviewDestination != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}
