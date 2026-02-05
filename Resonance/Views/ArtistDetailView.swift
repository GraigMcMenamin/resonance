//
//  ArtistDetailView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/22/26.
//

import SwiftUI

struct ArtistDetailView: View {
    let artistId: String
    let artistName: String
    let artistImageURL: URL?
    
    @StateObject private var spotifyService = SpotifyService()
    @EnvironmentObject var ratingsManager: RatingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var buddyManager: BuddyManager
    
    @State private var artist: SpotifyArtist?
    @State private var topTracks: [SpotifyTrack] = []
    @State private var albums: [SpotifyAlbum] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItem: RatableItem?
    @State private var showAllTracks = false
    @State private var buddies: [Buddy] = []
    @State private var buddyRatings: [UserRating] = []
    @State private var showSendSheet = false
    
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
                        Task { await loadArtistData() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Artist Header
                        artistHeader
                        
                        // Rating Section
                        ratingSection
                        
                        // Top Tracks Section
                        if !topTracks.isEmpty {
                            topTracksSection
                        }
                        
                        // Albums Section
                        if !albums.isEmpty {
                            albumsSection
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(artistName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedItem) { item in
            RatingSheet(item: item, ratingsManager: ratingsManager)
                .environmentObject(authManager)
                .environmentObject(firebaseService)
        }
        .sheet(isPresented: $showSendSheet) {
            SendMusicView(musicItem: MusicItemToSend(
                spotifyId: artistId,
                itemType: .artist,
                name: artist?.name ?? artistName,
                artistName: nil,
                imageURL: artist?.imageURL ?? artistImageURL
            ))
            .environmentObject(firebaseService)
            .environmentObject(authManager)
            .environmentObject(buddyManager)
        }
        .task {
            await spotifyService.authenticate()
            await loadArtistData()
            await loadBuddyRatings()
        }
        .onChange(of: ratingsManager.allRatings) { _, _ in
            updateBuddyRatings()
        }
    }
    
    // MARK: - Artist Header
    
    private var artistHeader: some View {
        VStack(spacing: 16) {
            // Artist Image - edge to edge with small padding, square with rounded corners
            GeometryReader { geometry in
                CustomAsyncImage(url: artist?.imageURL ?? artistImageURL) { phase in
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
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.3), radius: 10)
                    case .failure:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .overlay(
                                Image(systemName: "music.mic")
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
            .padding(.horizontal, 16)
            
            // Artist Name
            Text(artist?.name ?? artistName)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Rating Section
    
    private var ratingSection: some View {
        VStack(spacing: 20) {
            // Split rating display
            HStack(spacing: 40) {
                // User's Rating (Left side)
                if let userRating = getUserRating() {
                    VStack(spacing: 6) {
                        Text("you gave")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(userRating.percentage)%")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        RatingBar(percentage: Double(userRating.percentage))
                            .frame(width: 100, height: 8)
                    }
                }
                
                // Average Rating (Right side)
                if let average = ratingsManager.getAverageRating(for: artistId) {
                    VStack(spacing: 6) {
                        Text("average")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(Int(average))%")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        RatingBar(percentage: average)
                            .frame(width: 100, height: 8)
                    }
                }
            }
            
            // Rate & Review and Reviews Buttons
            HStack(spacing: 12) {
                Button(action: {
                    if let artist = artist {
                        selectedItem = .artist(artist)
                    }
                }) {
                    HStack(spacing: 6) {
                        Text("%")
                            .fontWeight(.bold)
                        Text(hasUserRating ? "update" : "rate & review")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.6, green: 0.4, blue: 0.8))
                    .cornerRadius(20)
                }
                .disabled(artist == nil)
                
                NavigationLink(destination: ReviewsListView(
                    spotifyId: artistId,
                    itemName: artist?.name ?? artistName,
                    artistName: nil,
                    imageURL: artist?.imageURL ?? artistImageURL,
                    reviewType: .artist
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble")
                        Text("reviews")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Send to Buddy Button
                if !authManager.isGuestMode {
                    Button(action: {
                        showSendSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane")
                            Text("send")
                        }
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
            
            // Buddy Ratings Section
            BuddyRatingsSection(buddyRatings: buddyRatings, buddies: buddies)
        }
        .padding(.horizontal)
    }
    
    private func getUserRating() -> UserRating? {
        guard let userId = authManager.currentUser?.id else { return nil }
        let ratingId = UserRating.makeId(userId: userId, spotifyId: artistId)
        return ratingsManager.getRating(for: ratingId)
    }
    
    private var hasUserRating: Bool {
        getUserRating() != nil
    }
    
    // MARK: - Buddy Ratings Loading
    
    private func loadBuddyRatings() async {
        guard let userId = authManager.currentUser?.id else { return }
        
        do {
            buddies = try await firebaseService.getBuddies(forUserId: userId)
            updateBuddyRatings()
        } catch {
            print("Error loading buddies: \(error)")
        }
    }
    
    private func updateBuddyRatings() {
        let buddyIds = buddies.map { $0.id }
        buddyRatings = ratingsManager.getBuddyRatings(for: artistId, buddyIds: buddyIds)
    }
    
    // MARK: - Top Tracks Section
    
    private var topTracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with column labels
            HStack {
                Text("top songs")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Column headers for ratings
                HStack(spacing: 10) {
                    Text("your %")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("avg %")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 50, alignment: .trailing)
                }
                .padding(.trailing, 20) // Account for chevron
            }
            .padding(.horizontal)
            
            VStack(spacing: 4) {
                ForEach(Array(topTracks.prefix(showAllTracks ? 10 : 5).enumerated()), id: \.element.id) { index, track in
                    NavigationLink(destination: SongDetailView(
                        trackId: track.id,
                        trackName: track.name,
                        artistName: track.artistNames,
                        albumName: track.album?.name,
                        albumId: track.album?.id,
                        imageURL: track.imageURL
                    )) {
                        TrackRowCompact(track: track, index: index + 1, ratingsManager: ratingsManager, userId: authManager.currentUser?.id)
                    }
                    .buttonStyle(.plain)
                }
                
                // See More / See Less button
                if topTracks.count > 5 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllTracks.toggle()
                        }
                    }) {
                        HStack {
                            Text(showAllTracks ? "See Less" : "See More")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: showAllTracks ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Albums Section
    
    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("albums")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(albums.prefix(10)) { album in
                        NavigationLink(destination: AlbumDetailView(
                            albumId: album.id,
                            albumName: album.name,
                            artistName: album.artistNames,
                            imageURL: album.imageURL
                        )) {
                            AlbumCardView(album: album, ratingsManager: ratingsManager, userId: authManager.currentUser?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadArtistData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            async let artistResult = spotifyService.getArtist(id: artistId)
            async let tracksResult = spotifyService.getArtistTopTracks(id: artistId)
            async let albumsResult = spotifyService.getArtistAlbums(id: artistId)
            
            artist = try await artistResult
            topTracks = try await tracksResult
            albums = try await albumsResult
        } catch {
            errorMessage = "Failed to load artist data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - Compact Track Row View (for Artist page)

struct TrackRowCompact: View {
    let track: SpotifyTrack
    let index: Int
    let ratingsManager: RatingsManager
    let userId: String?
    
    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 18)
            
            // Album artwork
            CustomAsyncImage(url: track.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .cornerRadius(6)
                default:
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.caption)
                                .foregroundColor(.gray)
                        )
                }
            }
            
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
            
            RatingBadgeCompact(spotifyId: track.id, ratingsManager: ratingsManager, userId: userId)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
        )
    }
}

// MARK: - Album Card View

struct AlbumCardView: View {
    let album: SpotifyAlbum
    let ratingsManager: RatingsManager
    let userId: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CustomAsyncImage(url: album.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 140, height: 140)
                        .cornerRadius(8)
                default:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 140, height: 140)
                        .overlay(
                            Image(systemName: "opticaldisc")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        )
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(album.releaseYear ?? " ")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                
                RatingBadgeCompact(spotifyId: album.id, ratingsManager: ratingsManager, userId: userId)
                    .frame(height: 20)
            }
            .frame(height: 60, alignment: .top)
        }
        .frame(width: 140)
    }
}

#Preview {
    NavigationView {
        ArtistDetailView(
            artistId: "06HL4z0CvFAxyc27GXpf02",
            artistName: "Taylor Swift",
            artistImageURL: nil
        )
    }
    .environmentObject(RatingsManager(firebaseService: FirebaseService()))
    .environmentObject(AuthenticationManager())
    .environmentObject(FirebaseService())
}
