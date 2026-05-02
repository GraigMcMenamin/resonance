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
    @StateObject private var viewModel = OtherUserReviewsViewModel()
    @State private var selectedFilter: RatingFilter = .all
    @State private var anchorId: String? = nil

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
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter Picker
            Picker("Filter", selection: $selectedFilter) {
                Text("all").tag(RatingFilter.all)
                Text("songs").tag(RatingFilter.songs)
                Text("artists").tag(RatingFilter.artists)
                Text("albums").tag(RatingFilter.albums)
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
                    } else if filteredRatings.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "star.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text("no ratings yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("this user hasn't rated any music yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(filteredRatings) { rating in
                            NavigationLink(destination: destinationView(for: rating)) {
                                RatingRow(rating: rating)
                            }
                            .id(rating.id)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    anchorId = rating.id
                                }
                            )
                            .onAppear {
                                if rating.id == filteredRatings.last?.id,
                                   viewModel.hasMore {
                                    Task { await viewModel.loadMore(firebaseService: firebaseService) }
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
        .navigationTitle(user.username.map { "@\($0)'s ratings" } ?? "ratings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await viewModel.load(userId: user.id, firebaseService: firebaseService)
            }
        }
    }

    // MARK: - Navigation Destinations

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
