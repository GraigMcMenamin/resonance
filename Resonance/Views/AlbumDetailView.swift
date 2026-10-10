//
//  AlbumDetailView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/22/26.
//

import SwiftUI

struct AlbumDetailView: View {
    let albumId: String
    let albumName: String
    let artistName: String
    let imageURL: URL?
    
    @EnvironmentObject var spotifyService: SpotifyService
    @EnvironmentObject var ratingsManager: RatingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var buddyManager: BuddyManager
    @EnvironmentObject var rankingsManager: RankingsManager
    @EnvironmentObject var listenListManager: ListenListManager
    
    @State private var album: SpotifyAlbumFull?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItem: RatableItem?
    @State private var buddies: [Buddy] = []
    @State private var buddyRatings: [UserRating] = []
    @State private var showSendSheet = false
    @State private var itemUserRating: UserRating?
    @State private var showRankAllSongsSheet = false
    @State private var showAddToListenListSheet = false
    /// Track average ratings fetched locally — never writes to the global allRatings store.
    @State private var trackAverageRatings: [String: Double] = [:]
    
    var body: some View {
        ZStack {
            Color(red: 0.15, green: 0.08, blue: 0.18)
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
                        Task { await loadAlbumData() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        // Album Header
                        albumHeader
                        
                        // Rating Section
                        ratingSection
                        
                        // Tracks Section
                        if let tracks = album?.tracks.items, !tracks.isEmpty {
                            tracksSection(tracks: tracks)
                        }
                        
                        // Album Info
                        if album != nil {
                            albumInfoSection
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in
            RatingSheet(item: item, ratingsManager: ratingsManager)
                .environmentObject(authManager)
                .environmentObject(firebaseService)
        }
        .sheet(isPresented: $showSendSheet) {
            SendMusicView(musicItem: MusicItemToSend(
                spotifyId: albumId,
                itemType: .album,
                name: album?.name ?? albumName,
                artistName: album?.artistNames ?? artistName,
                imageURL: album?.imageURL ?? imageURL
            ))
            .environmentObject(firebaseService)
            .environmentObject(authManager)
            .environmentObject(buddyManager)
        }
        .fullScreenCover(isPresented: $showRankAllSongsSheet) {
            CreateRankingView(
                rankingsManager: rankingsManager,
                presetAlbumId: albumId,
                presetAlbumName: album?.name ?? albumName
            )
        }
        .sheet(isPresented: $showAddToListenListSheet) {
            AddToListenListSheet(
                spotifyId: albumId,
                type: .album,
                name: album?.name ?? albumName,
                artistName: album?.artistNames ?? artistName,
                imageURL: album?.imageURL ?? imageURL
            )
            .environmentObject(listenListManager)
        }
        .task {
            if !spotifyService.isAuthenticated {
                await spotifyService.authenticate()
            }
            async let albumLoad: Void = loadAlbumData()
            async let buddyLoad: Void = loadBuddyRatings()
            async let userRatingLoad: Void = fetchUserRating()
            await albumLoad
            await buddyLoad
            await userRatingLoad
        }
    }
    
    // MARK: - Album Header
    
    private var albumHeader: some View {
        VStack(spacing: 10) {
            // Album Art - edge to edge with small padding
            GeometryReader { geometry in
                CustomAsyncImage(url: album?.imageURL ?? imageURL) { phase in
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
                                Image(systemName: "opticaldisc")
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
                    title: album?.name ?? albumName,
                    artists: album?.artists ?? [],
                    ratingsManager: ratingsManager
                )
                playButton
            }
            .padding(.top, 12)
        }
        .padding(.top, 8)
        .padding(.horizontal)
    }
    
    // Open in Spotify
    private var playButton: some View {
        Button(action: {
            if let uri = SpotifyService.spotifyURI(type: "album", id: albumId),
               UIApplication.shared.canOpenURL(uri) {
                UIApplication.shared.open(uri)
            } else if let webURL = SpotifyService.spotifyWebURL(type: "album", id: albumId) {
                UIApplication.shared.open(webURL)
            }
        }) {
            Image(systemName: "play.circle.fill")
                .font(.largeTitle)
                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
        }
    }
    
    // MARK: - Rating Section
    
    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Average rating (hidden entirely when there is none)
            if let average = ratingsManager.getAverageRating(for: albumId) {
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
                    spotifyId: albumId,
                    itemName: album?.name ?? albumName,
                    artistName: album?.artistNames ?? artistName,
                    imageURL: album?.imageURL ?? imageURL,
                    reviewType: .album
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
                    if let album = album {
                        selectedItem = .album(SpotifyAlbum(
                            id: album.id,
                            name: album.name,
                            artists: album.artists,
                            images: album.images,
                            releaseDate: album.releaseDate,
                            totalTracks: album.totalTracks
                        ))
                    }
                }) {
                    Text(hasUserRating ? "edit review" : "review")
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color(red: 0.6, green: 0.4, blue: 0.8))
                    .cornerRadius(20)
                }
                .disabled(album == nil)
            }
            
            // Add To Listen List / Rank All Songs Buttons
            HStack(spacing: 28) {
                Button(action: { showAddToListenListSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: listenListManager.contains(spotifyId: albumId) ? "checkmark.circle" : "plus.circle")
                        Text(listenListManager.contains(spotifyId: albumId) ? "on listen list" : "add to listen list")
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                }
                
                if let tracks = album?.tracks.items, !tracks.isEmpty {
                    Button(action: { showRankAllSongsSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "list.number")
                            Text("rank all songs")
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            
            // Buddy Ratings Section
            BuddyRatingsSection(
                buddyRatings: buddyRatings,
                buddies: buddies,
                userRating: getUserRating(),
                spotifyId: albumId,
                itemName: album?.name ?? albumName,
                artistName: album?.artistNames ?? artistName,
                imageURL: album?.imageURL ?? imageURL,
                reviewType: .album,
                showHeader: false
            )
        }
        .padding(.horizontal)
    }
    
    private func getUserRating() -> UserRating? {
        guard let userId = authManager.currentUser?.id else { return nil }
        let ratingId = UserRating.makeId(userId: userId, spotifyId: albumId)
        return ratingsManager.getRating(for: ratingId) ?? itemUserRating
    }
    
    private var hasUserRating: Bool {
        getUserRating() != nil
    }
    
    // MARK: - Buddy Ratings Loading

    private func fetchUserRating() async {
        guard let userId = authManager.currentUser?.id else { return }
        let ratingId = UserRating.makeId(userId: userId, spotifyId: albumId)
        itemUserRating = try? await firebaseService.getRating(id: ratingId)
    }

    private func loadBuddyRatings() async {
        guard let userId = authManager.currentUser?.id else { return }
        do {
            buddies = try await firebaseService.getBuddies(forUserId: userId)
            let buddyIds = buddies.map { $0.id }
            buddyRatings = try await firebaseService.fetchRatingsForItemByUsers(spotifyId: albumId, userIds: buddyIds)
        } catch {
            print("Error loading buddy ratings: \(error)")
        }
    }
    
    
    // MARK: - Tracks Section
    
    private func tracksSection(tracks: [SpotifyTrackSimple]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with column labels
            HStack {
                Text("songs")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Column header for average rating, only when any track has a rating
                if tracks.contains(where: { (trackAverageRatings[$0.id] ?? ratingsManager.getAverageRating(for: $0.id)) != nil }) {
                    VStack(spacing: 1) {
                        Text("average")
                        Text("rating")
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 55, alignment: .center)
                    .padding(.trailing, 32) // Account for row inner padding + chevron spacing + chevron width
                }
            }
            .padding(.horizontal)
            
            VStack(spacing: 4) {
                ForEach(tracks) { track in
                    NavigationLink(destination: SongDetailView(
                        trackId: track.id,
                        trackName: track.name,
                        artistName: track.artistNames,
                        albumName: album?.name,
                        albumId: album?.id,
                        imageURL: album?.imageURL
                    )) {
                        AlbumTrackRowView(
                            track: track,
                            albumImageURL: album?.imageURL,
                            ratingsManager: ratingsManager,
                            userId: authManager.currentUser?.id,
                            averageRatingOverride: trackAverageRatings[track.id]
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Album Info Section
    
    private var albumInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let label = album?.label {
                Text("Label: \(label)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            if let copyrights = album?.copyrights?.first {
                Text(copyrights.text)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    
    // MARK: - Data Loading
    
    private func loadAlbumData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            album = try await spotifyService.getAlbum(id: albumId)
        } catch {
            errorMessage = "Failed to load album data: \(error.localizedDescription)"
        }
        
        isLoading = false
        
        // Fetch track ratings into local state — never mutates the global allRatings,
        // so parent views (e.g. SongDetailView) are never invalidated and the
        // NavigationLink cannot pop unexpectedly.
        if let trackIds = album?.tracks.items.map({ $0.id }), !trackIds.isEmpty {
            if let fetched = try? await firebaseService.fetchAverageRatings(for: trackIds) {
                trackAverageRatings = fetched
            }
        }
    }
}

// MARK: - Album Track Row View

struct AlbumTrackRowView: View {
    let track: SpotifyTrackSimple
    let albumImageURL: URL?
    @ObservedObject var ratingsManager: RatingsManager
    let userId: String?
    var averageRatingOverride: Double? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            // Track Number
            Text("\(track.trackNumber ?? 0)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 20)
            
            // Track Info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(track.artistNames)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Rating
            RatingBadgeCompact(spotifyId: track.id, ratingsManager: ratingsManager, userId: userId, averageRatingOverride: averageRatingOverride)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }
}

#Preview {
    NavigationView {
        AlbumDetailView(
            albumId: "1NAmidJlEaVgA3MpcPFYGq",
            albumName: "1989",
            artistName: "Taylor Swift",
            imageURL: nil
        )
    }
    .environmentObject(RatingsManager(firebaseService: FirebaseService()))
    .environmentObject(AuthenticationManager())
    .environmentObject(FirebaseService())
}
