//
//  BoardSort.swift
//  Resonance
//
//  Sort options shared by "my board" (BuddyBoardView) and other users' boards (OtherUserReviewsView).
//

import SwiftUI

enum BoardSortOption: String, CaseIterable, Identifiable {
    case dateNewest = "date: newest first"
    case dateOldest = "date: oldest first"
    case ratingHighest = "rating: high to low"
    case ratingLowest = "rating: low to high"
    case ratedByMe = "music i've also rated"
    case writtenReviews = "written reviews only"

    var id: String { rawValue }

    /// Only the default order matches the server's paging order, so every other option needs the full list.
    var needsAllRatings: Bool { self != .dateNewest }

    static func options(forOtherUser: Bool) -> [BoardSortOption] {
        forOtherUser ? allCases : allCases.filter { $0 != .ratedByMe }
    }

    /// `ratedByMeIds` is only used by `.ratedByMe`.
    func arrange(ratings: [UserRating], rankings: [UserRanking], ratedByMeIds: Set<String> = []) -> [BuddyFeedItem] {
        switch self {
        case .dateNewest:
            return (ratings.map { .rating($0) } + rankings.map { .ranking($0) }).sorted { $0.date > $1.date }
        case .dateOldest:
            return (ratings.map { .rating($0) } + rankings.map { .ranking($0) }).sorted { $0.date < $1.date }
        case .ratingHighest, .ratingLowest:
            let highestFirst = self == .ratingHighest
            let sortedRatings = ratings.sorted { a, b in
                if a.percentage != b.percentage {
                    return highestFirst ? a.percentage > b.percentage : a.percentage < b.percentage
                }
                return a.dateRated > b.dateRated
            }
            // Rankings have no percentage, so they follow the ratings, newest first.
            let sortedRankings = rankings.sorted { ($0.dateUpdated ?? $0.dateCreated) > ($1.dateUpdated ?? $1.dateCreated) }
            return sortedRatings.map { .rating($0) } + sortedRankings.map { .ranking($0) }
        case .writtenReviews:
            return ratings
                .filter { $0.hasReviewContent }
                .sorted { $0.dateRated > $1.dateRated }
                .map { .rating($0) }
        case .ratedByMe:
            return ratings
                .filter { ratedByMeIds.contains($0.spotifyId) }
                .sorted { a, b in
                    a.percentage != b.percentage ? a.percentage > b.percentage : a.dateRated > b.dateRated
                }
                .map { .rating($0) }
        }
    }
}

struct BoardSortMenu: View {
    @Binding var selection: BoardSortOption
    let options: [BoardSortOption]

    var body: some View {
        Menu {
            Picker("sort", selection: $selection) {
                ForEach(options) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text("sort")
            }
            .font(.subheadline)
            .foregroundColor(.white)
        }
    }
}
