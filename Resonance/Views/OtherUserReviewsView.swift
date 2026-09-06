//
//  OtherUserReviewsView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 5/1/26.
//

import SwiftUI
import Combine

struct OtherUserReviewsView: View {
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var rankingsManager: RankingsManager
    @StateObject private var viewModel = OtherUserReviewsViewModel()
    @State private var selectedFilter: RatingFilter = .all
    @State private var anchorId: String? = nil
    @State private var reviewNavRating: UserRating? = nil
    @State private var musicNavRating: UserRating? = nil
    @State private var rankingNav: UserRanking? = nil

    let user: AppUser

    private var filteredRatings: [UserRating] {
        switch selectedFilter {
        case .all:
            return viewModel.ratings
        case .artists:
            return viewModel.ratings.filter { $0.type == .artist }
        case .albums:
            return viewModel.ratings.filter { $0.type == .album }
        case .songs:
            return viewModel.ratings.filter { $0.type == .track }
        case .rankings:
            return []
        }
    }
    
    private var filteredRankings: [UserRanking] {
        let theirs = rankingsManager.rankings(forUserId: user.id)
        switch selectedFilter {
        case .all, .rankings:
            return theirs
        case .artists, .albums, .songs:
            return []
        }
    }
    
    /// Ratings and rankings merged into a single, date-sorted feed so they display the same way.
    private var boardItems: [BuddyFeedItem] {
        var items: [BuddyFeedItem] = filteredRatings.map { .rating($0) }
        items += filteredRankings.map { .ranking($0) }
        return items.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hidden NavigationLink for review text navigation
            NavigationLink(
                destination: reviewsListView(for: reviewNavRating),
                isActive: Binding(
                    get: { reviewNavRating != nil },
                    set: { if !$0 { reviewNavRating = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)

            // Hidden NavigationLink for music view navigation
            NavigationLink(
                destination: Group {
                    if let r = musicNavRating { destinationView(for: r) }
                },
                isActive: Binding(
                    get: { musicNavRating != nil },
                    set: { if !$0 { musicNavRating = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)

            // Hidden NavigationLink for ranking detail navigation
            NavigationLink(
                destination: Group {
                    if let ranking = rankingNav { RankingDetailView(ranking: ranking) }
                },
                isActive: Binding(
                    get: { rankingNav != nil },
                    set: { if !$0 { rankingNav = nil } }
                )
            ) {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)

            // Filter Picker
            Picker("Filter", selection: $selectedFilter) {
                Text("all").tag(RatingFilter.all)
                Text("songs").tag(RatingFilter.songs)
                Text("artists").tag(RatingFilter.artists)
                Text("albums").tag(RatingFilter.albums)
                Text("rankings").tag(RatingFilter.rankings)
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: selectedFilter) { _ in
                anchorId = nil
            }

            ScrollViewReader { proxy in
                List {
                    if viewModel.isLoading && viewModel.ratings.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else if filteredRatings.isEmpty && filteredRankings.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "star.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text(selectedFilter == .rankings ? "no rankings yet" : "no ratings yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(selectedFilter == .rankings ? "this user hasn't made any rankings yet" : "this user hasn't rated any music yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(boardItems) { item in
                            Group {
                                switch item {
                                case .rating(let rating):
                                    RatingRow(rating: rating, onReviewTapped: rating.hasReviewContent ? { reviewNavRating = rating } : nil)
                                        .onAppear {
                                            if rating.id == filteredRatings.last?.id,
                                               viewModel.hasMore {
                                                Task { await viewModel.loadMore(firebaseService: firebaseService) }
                                            }
                                        }
                                case .ranking(let ranking):
                                    RankingRow(ranking: ranking)
                                case .recommendation:
                                    EmptyView()
                                }
                            }
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                anchorId = item.id
                                switch item {
                                case .rating(let rating):
                                    musicNavRating = rating
                                case .ranking(let ranking):
                                    rankingNav = ranking
                                case .recommendation:
                                    break
                                }
                            }
                        }

                        if viewModel.isLoading && !viewModel.ratings.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.refresh(userId: user.id, firebaseService: firebaseService)
                }
                .onAppear {
                    if let anchor = anchorId {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.none) {
                                proxy.scrollTo(anchor, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(user.username.map { "@\($0)'s board" } ?? "board")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await viewModel.load(userId: user.id, firebaseService: firebaseService)
            }
        }
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func reviewsListView(for rating: UserRating?) -> some View {
        if let rating = rating {
            let reviewType: Review.ReviewType = {
                switch rating.type {
                case .artist: return .artist
                case .album: return .album
                case .track: return .track
                }
            }()
            ReviewsListView(
                spotifyId: rating.spotifyId,
                itemName: rating.name,
                artistName: rating.artistName,
                imageURL: rating.imageURL.flatMap { URL(string: $0) },
                reviewType: reviewType,
                scrollToReviewId: rating.id,
                initialSelectedLength: rating.reviewLength ?? .short
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func destinationView(for rating: UserRating) -> some View {
        switch rating.type {
        case .artist:
            ArtistDetailView(
                artistId: rating.spotifyId,
                artistName: rating.name,
                artistImageURL: rating.imageURL.flatMap { URL(string: $0) }
            )
        case .album:
            AlbumDetailView(
                albumId: rating.spotifyId,
                albumName: rating.name,
                artistName: rating.artistName ?? "",
                imageURL: rating.imageURL.flatMap { URL(string: $0) }
            )
        case .track:
            SongDetailView(
                trackId: rating.spotifyId,
                trackName: rating.name,
                artistName: rating.artistName ?? "",
                albumName: nil,
                albumId: nil,
                imageURL: rating.imageURL.flatMap { URL(string: $0) }
            )
        }
    }
}

// MARK: - View Model

@MainActor
class OtherUserReviewsViewModel: ObservableObject {
    @Published var ratings: [UserRating] = []
    @Published var isLoading = false
    @Published var hasMore = false

    private var didLoad = false

    func load(userId: String, firebaseService: FirebaseService) async {
        guard !didLoad else { return }
        isLoading = true
        firebaseService.resetUserRatingsPagination(for: userId)
        do {
            let result = try await firebaseService.fetchNextUserRatingsPage(userId: userId)
            ratings = result.ratings
            hasMore = result.hasMore
        } catch {
            print("OtherUserReviewsViewModel: error loading ratings: \(error)")
        }
        isLoading = false
        didLoad = true
    }

    func loadMore(firebaseService: FirebaseService) async {
        guard hasMore, !isLoading, let userId = ratings.first?.userId else { return }
        isLoading = true
        do {
            let result = try await firebaseService.fetchNextUserRatingsPage(userId: userId)
            ratings.append(contentsOf: result.ratings)
            hasMore = result.hasMore
        } catch {
            print("OtherUserReviewsViewModel: error loading more ratings: \(error)")
        }
        isLoading = false
    }

    func refresh(userId: String, firebaseService: FirebaseService) async {
        didLoad = false
        ratings = []
        hasMore = false
        await load(userId: userId, firebaseService: firebaseService)
    }
}
