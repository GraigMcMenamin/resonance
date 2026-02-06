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
    let ratingsManager: RatingsManager
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

/// Compact version for list items
struct RatingBadgeCompact: View {
    let spotifyId: String
    let ratingsManager: RatingsManager
    let userId: String?
    
    private var userRating: UserRating? {
        guard let userId = userId else { return nil }
        let ratingId = UserRating.makeId(userId: userId, spotifyId: spotifyId)
        return ratingsManager.getRating(for: ratingId)
    }
    
    private var averageRating: Double? {
        ratingsManager.getAverageRating(for: spotifyId)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // User's rating - shown first (left side)
            if let rating = userRating {
                Text("\(rating.percentage)%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            
            // Average rating - shown second (right side), bigger with bar below
            if let average = averageRating {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(Int(average))%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Colored rating bar below
                    RatingBarMini(percentage: average)
                        .frame(width: 50, height: 6)
                }
            }
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
    @State private var showAllRatings = false
    
    private var displayedRatings: [UserRating] {
        if showAllRatings || buddyRatings.count <= 3 {
            return buddyRatings
        } else {
            return Array(buddyRatings.prefix(3))
        }
    }
    
    /// Find buddy info for a given userId
    private func buddyInfo(for userId: String) -> Buddy? {
        return buddies.first { $0.id == userId }
    }
    
    var body: some View {
        if !buddyRatings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("buddy ratings")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.6))
                    .textCase(.lowercase)
                
                VStack(spacing: 8) {
                    ForEach(displayedRatings) { rating in
                        let buddy = buddyInfo(for: rating.userId)
                        NavigationLink(destination: BuddyProfileDestination(userId: rating.userId)) {
                            BuddyRatingRow(
                                rating: rating,
                                username: buddy?.username ?? rating.username,
                                imageURL: buddy?.imageURL ?? rating.userImageURL
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // See More / See Less button
                    if buddyRatings.count > 3 {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllRatings.toggle()
                            }
                        }) {
                            HStack {
                                Text(showAllRatings ? "see less" : "see more (\\(buddyRatings.count - 3) more)")
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
    @EnvironmentObject var firebaseService: FirebaseService
    @State private var user: AppUser?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
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
            do {
                user = try await firebaseService.getUserProfile(userId: userId)
            } catch {
                print("Error fetching user: \(error)")
            }
            isLoading = false
        }
    }
}

/// A single row displaying a buddy's rating
struct BuddyRatingRow: View {
    let rating: UserRating
    let username: String?
    let imageURL: String?
    
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
        } else {
            return "User"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Buddy profile picture
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
            
            // Buddy username (with @ prefix if it's a username)
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
            
            // Chevron to indicate tappable
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
}
