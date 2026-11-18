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
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var viewModel = OtherUserReviewsViewModel()
    @State private var selectedFilter: RatingFilter = .all
    @State private var selectedSort: BoardSortOption = .dateNewest
    @State private var loadFailed = false
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
    
    /// Ratings and rankings merged into a single feed (ordered by the selected sort) so they display the same way.
    private var boardItems: [BuddyFeedItem] {
        // Partial data would give a wrong order, so hold back until everything the sort needs is in.
        if isPreparingSort { return [] }
        return selectedSort.arrange(
            ratings: filteredRatings,
            rankings: filteredRankings,
            ratedByMeIds: viewModel.ratedByMeIds ?? []
        )
    }

    private var isPreparingSort: Bool {
        guard selectedSort.needsAllRatings, selectedFilter != .rankings, !loadFailed, viewModel.didLoad else { return false }
        return viewModel.hasMore || (selectedSort == .ratedByMe && viewModel.ratedByMeIds == nil)
    }

    private func loadDataForSort() {
        guard selectedSort.needsAllRatings, selectedFilter != .rankings, !loadFailed,
              viewModel.didLoad, !viewModel.isLoading else { return }
        Task {
            var succeeded = true
            if viewModel.hasMore {
                succeeded = await viewModel.loadAll(firebaseService: firebaseService)
            }
            if succeeded, selectedSort == .ratedByMe, viewModel.ratedByMeIds == nil,
               let myId = authManager.currentUser?.id {
                succeeded = await viewModel.loadRatedByMe(currentUserId: myId, firebaseService: firebaseService)
            }
            if !succeeded { loadFailed = true }
        }
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
                loadDataForSort()
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
                    } else if isPreparingSort {
                        HStack {
                            Spacer()
                            ProgressView("loading all ratings...")
                            Spacer()
                        }
                        .padding(.vertical, 60)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else if boardItems.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "star.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text(emptyTitle)
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(emptySubtitle)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                BoardSortMenu(selection: $selectedSort, options: BoardSortOption.options(forOtherUser: true))
            }
        }
        .onChange(of: selectedSort) { _ in
            anchorId = nil
            loadFailed = false
            loadDataForSort()
        }
        .onChange(of: viewModel.isLoading) { _ in loadDataForSort() }
        .onAppear {
            Task {
                await viewModel.load(userId: user.id, firebaseService: firebaseService)
            }
        }
    }

    private var emptyTitle: String {
        switch (selectedFilter, selectedSort) {
        case (.rankings, _): return "no rankings yet"
        case (_, .writtenReviews): return "no written reviews"
        case (_, .ratedByMe): return "no shared music"
        default: return "no ratings yet"
        }
    }

    private var emptySubtitle: String {
        switch (selectedFilter, selectedSort) {
        case (.rankings, _): return "this user hasn't made any rankings yet"
        case (_, .writtenReviews): return "this user hasn't written any reviews here"
        case (_, .ratedByMe): return "you haven't rated any of the same music"
        default: return "this user hasn't rated any music yet"
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
    @Published private(set) var didLoad = false
    /// Spotify IDs from `ratings` that the signed-in user has also rated; nil until looked up.
    @Published var ratedByMeIds: Set<String>? = nil

    private var userId: String?

    func load(userId: String, firebaseService: FirebaseService) async {
        guard !didLoad else { return }
        self.userId = userId
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

    /// Pulls every remaining page in large chunks, publishing once at the end.
    func loadAll(firebaseService: FirebaseService) async -> Bool {
        guard hasMore, !isLoading, let userId = userId else { return true }
        isLoading = true
        var collected: [UserRating] = []
        var finished = false
        do {
            var more = true
            while more {
                let result = try await firebaseService.fetchNextUserRatingsPage(userId: userId, limit: 300)
                collected.append(contentsOf: result.ratings)
                more = result.hasMore
            }
            finished = true
        } catch {
            print("OtherUserReviewsViewModel: error loading all ratings: \(error)")
        }
        let existingIds = Set(ratings.map { $0.id })
        ratings.append(contentsOf: collected.filter { !existingIds.contains($0.id) })
        if finished { hasMore = false }
        isLoading = false
        return finished
    }

    func loadRatedByMe(currentUserId: String, firebaseService: FirebaseService) async -> Bool {
        do {
            ratedByMeIds = try await firebaseService.fetchRatedSpotifyIds(
                userId: currentUserId,
                among: Array(Set(ratings.map { $0.spotifyId }))
            )
            return true
        } catch {
            print("OtherUserReviewsViewModel: error loading shared ratings: \(error)")
            return false
        }
    }

    func refresh(userId: String, firebaseService: FirebaseService) async {
        didLoad = false
        ratings = []
        hasMore = false
        ratedByMeIds = nil
        await load(userId: userId, firebaseService: firebaseService)
    }
}
