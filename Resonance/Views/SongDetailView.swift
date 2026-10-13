//
//  SongDetailView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/22/26.
//

import SwiftUI

struct SongDetailView: View {
    let trackId: String
    let trackName: String
    let artistName: String
    let albumName: String?
    let albumId: String?
    let imageURL: URL?
    
    @EnvironmentObject var spotifyService: SpotifyService
    @EnvironmentObject var ratingsManager: RatingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var buddyManager: BuddyManager
    @EnvironmentObject var rankingsManager: RankingsManager
    @EnvironmentObject var listenListManager: ListenListManager
    
    @State private var track: SpotifyTrack?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItem: RatableItem?
    @State private var buddies: [Buddy] = []
    @State private var buddyRatings: [UserRating] = []
    @State private var showSendSheet = false
    @State private var showAddToRankingSheet = false
    @State private var showAddToListenListSheet = false
    @State private var itemUserRating: UserRating?
    /// Explicitly fetched album average — never writes to the global allRatings store.
    @State private var albumAverageRating: Double?
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadTrackData() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        // Song Header
                        songHeader
                        
                        // Rating Section
                        ratingSection
                        
                        // Album Section
                        albumSection
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .solidPurpleTopBar()
        .sheet(item: $selectedItem) { item in
            RatingSheet(item: item, ratingsManager: ratingsManager)
                .environmentObject(authManager)
                .environmentObject(firebaseService)
        }
        .sheet(isPresented: $showSendSheet) {
            SendMusicView(musicItem: MusicItemToSend(
                spotifyId: trackId,
                itemType: .track,
                name: track?.name ?? trackName,
                artistName: track?.artistNames ?? artistName,
                imageURL: track?.imageURL ?? imageURL
            ))
            .environmentObject(firebaseService)
            .environmentObject(authManager)
            .environmentObject(buddyManager)
        }
        .sheet(isPresented: $showAddToRankingSheet) {
            AddToRankingSheet(
                entry: RankingEntry(
                    spotifyId: trackId,
                    name: track?.name ?? trackName,
                    artistName: track?.artistNames ?? artistName,
                    imageURL: (track?.imageURL ?? imageURL)?.absoluteString
                ),
                type: .track
            )
            .environmentObject(rankingsManager)
            .environmentObject(authManager)
            .environmentObject(spotifyService)
        }
        .sheet(isPresented: $showAddToListenListSheet) {
            AddToListenListSheet(
                spotifyId: trackId,
                type: .track,
                name: track?.name ?? trackName,
                artistName: track?.artistNames ?? artistName,
                imageURL: track?.imageURL ?? imageURL
            )
            .environmentObject(listenListManager)
        }
        .task {
            if !spotifyService.isAuthenticated {
                await spotifyService.authenticate()
            }
            async let trackLoad: Void = loadTrackData()
            async let buddyLoad: Void = loadBuddyRatings()
            async let userRatingLoad: Void = fetchUserRating()
            async let albumAverageLoad: Void = fetchAlbumAverageRating()
            await trackLoad
            await buddyLoad
            await userRatingLoad
            await albumAverageLoad
        }
    }
    
    // MARK: - Song Header
    
    private var songHeader: some View {
        VStack(spacing: 10) {
            // Album Art - edge to edge with small padding
            GeometryReader { geometry in
                CustomAsyncImage(url: track?.imageURL ?? imageURL) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .overlay(ProgressView())
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.3), radius: 15)
                    case .failure:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                            )
                    @unknown default:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: geometry.size.width, height: geometry.size.width)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 40)
            
            HStack(alignment: .top, spacing: 12) {
                TitleArtistHeader(
                    title: track?.name ?? trackName,
                    artists: track?.artists ?? [],
                    ratingsManager: ratingsManager
                )
                playButton
            }
            .padding(.top, 12)
        }
        .padding(.top, 32)
        .padding(.horizontal)
    }
    
    // Open in Spotify
    private var playButton: some View {
        Button(action: {
            if let uri = SpotifyService.spotifyURI(type: "track", id: trackId),
               UIApplication.shared.canOpenURL(uri) {
                UIApplication.shared.open(uri)
            } else if let webURL = SpotifyService.spotifyWebURL(type: "track", id: trackId) {
                UIApplication.shared.open(webURL)
            }
        }) {
            Image(systemName: "play.circle.fill")
                .font(.largeTitle)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.buttonPurple)
        }
    }
    
    // MARK: - Rating Section
    
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Average rating (hidden entirely when there is none)
            if let average = ratingsManager.getAverageRating(for: trackId) {
                HStack(spacing: 8) {
                    RatingBar(percentage: average)
                        .frame(width: 100, height: 8)
                    Text("\(Int(average))%")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            
            // Reviews, Send (left) and review button (right)
            HStack(spacing: 28) {
                NavigationLink(destination: ReviewsListView(
                    spotifyId: trackId,
                    itemName: track?.name ?? trackName,
                    artistName: track?.artistNames ?? artistName,
                    imageURL: track?.imageURL ?? imageURL,
                    reviewType: .track
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble")
                        Text("reviews")
                            .lineLimit(1)
                    }
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
                }
                
                // Send to Buddy Button
                if !authManager.isGuestMode {
                    Button(action: {
                        showSendSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane")
                            Text("send")
                                .lineLimit(1)
                        }
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                Spacer(minLength: 8)
                
                Button(action: {
                    if let track = track {
                        selectedItem = .track(track)
                    }
                }) {
                    Text(hasUserRating ? "edit review" : "review")
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color.buttonPurple)
                    .cornerRadius(20)
                }
                .disabled(track == nil)
            }
            
            // Add To Listen List / Add To Ranking Buttons
            HStack(spacing: 28) {
                Button(action: { showAddToListenListSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: listenListManager.contains(spotifyId: trackId) ? "checkmark.circle" : "plus.circle")
                        Text(listenListManager.contains(spotifyId: trackId) ? "on listen list" : "add to listen list")
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                }
                
                Button(action: { showAddToRankingSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.number")
                        Text("add to a ranking")
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                }
            }
            
            // Buddy Ratings Section
            BuddyRatingsSection(
                buddyRatings: buddyRatings,
                buddies: buddies,
                userRating: getUserRating(),
                spotifyId: trackId,
                itemName: track?.name ?? trackName,
                artistName: track?.artistNames ?? artistName,
                imageURL: track?.imageURL ?? imageURL,
                reviewType: .track,
                showHeader: false
            )
        }
        .padding(.horizontal)
    }
    
    private var hasUserRating: Bool {
        getUserRating() != nil
    }
    
    private func getUserRating() -> UserRating? {
        guard let userId = authManager.currentUser?.id else { return nil }
        let ratingId = UserRating.makeId(userId: userId, spotifyId: trackId)
        return ratingsManager.getRating(for: ratingId) ?? itemUserRating
    }

    // MARK: - Buddy Ratings Loading

    private func fetchUserRating() async {
        guard let userId = authManager.currentUser?.id else { return }
        let ratingId = UserRating.makeId(userId: userId, spotifyId: trackId)
        itemUserRating = try? await firebaseService.getRating(id: ratingId)
    }

    private func loadBuddyRatings() async {
        guard let userId = authManager.currentUser?.id else { return }
        do {
            buddies = try await firebaseService.getBuddies(forUserId: userId)
            let buddyIds = buddies.map { $0.id }
            buddyRatings = try await firebaseService.fetchRatingsForItemByUsers(spotifyId: trackId, userIds: buddyIds)
        } catch {
            print("Error loading buddy ratings: \(error)")
        }
    }
    
    private func fetchAlbumAverageRating() async {
        guard let albumId = albumId else { return }
        if let fetched = try? await firebaseService.fetchAverageRatings(for: [albumId]) {
            albumAverageRating = fetched[albumId]
        }
    }
    
    
    // MARK: - Album Section
    
    @ViewBuilder
    private var albumSection: some View {
        if let album = track?.album {
            VStack(alignment: .leading, spacing: 12) {
                // Header row with column labels
                HStack {
                    Text("album")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Column header for average rating, only when there is a rating to show
                    if (albumAverageRating ?? ratingsManager.getAverageRating(for: album.id)) != nil {
                        Text("average rating")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 50, alignment: .trailing)
                            .padding(.trailing, 12) // Match row inner padding
                    }
                }
                
                NavigationLink(destination: AlbumDetailView(
                    albumId: album.id,
                    albumName: album.name,
                    artistName: track?.artistNames ?? artistName,
                    imageURL: album.imageURL
                )) {
                    HStack(spacing: 12) {
                        CustomAsyncImage(url: album.imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                            default:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Image(systemName: "opticaldisc")
                                            .foregroundColor(.gray)
                                    )
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(album.name)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Text(track?.artistNames ?? artistName)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        RatingBadgeCompact(spotifyId: album.id, ratingsManager: ratingsManager, userId: authManager.currentUser?.id, averageRatingOverride: albumAverageRating)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        } else if let albumName = albumName, let albumId = albumId {
            // Fallback when we have album info but not the full album object
            VStack(alignment: .leading, spacing: 12) {
                Text("Album")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                NavigationLink(destination: AlbumDetailView(
                    albumId: albumId,
                    albumName: albumName,
                    artistName: artistName,
                    imageURL: imageURL
                )) {
                    HStack(spacing: 12) {
                        CustomAsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                            default:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Image(systemName: "opticaldisc")
                                            .foregroundColor(.gray)
                                    )
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(albumName)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Text(artistName)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        RatingBadgeCompact(spotifyId: albumId, ratingsManager: ratingsManager, userId: authManager.currentUser?.id, averageRatingOverride: albumAverageRating)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadTrackData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            track = try await spotifyService.getTrack(id: trackId)
        } catch {
            errorMessage = "Failed to load track data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

#Preview {
    NavigationView {
        SongDetailView(
            trackId: "0V3wPSX9ygBnCm8psDIegu",
            trackName: "Anti-Hero",
            artistName: "Taylor Swift",
            albumName: "Midnights",
            albumId: "151w1FgRZfnKZA9FEcg9Z3",
            imageURL: nil
        )
    }
    .environmentObject(RatingsManager(firebaseService: FirebaseService()))
    .environmentObject(AuthenticationManager())
    .environmentObject(FirebaseService())
}
