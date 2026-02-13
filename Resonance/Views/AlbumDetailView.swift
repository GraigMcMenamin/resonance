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
    
    @State private var album: SpotifyAlbumFull?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItem: RatableItem?
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
                        Task { await loadAlbumData() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Album Header
                        albumHeader
                        
                        // Rating Section
                        ratingSection
                        
                        // Artist Section
                        artistSection
                        
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
        .navigationTitle(albumName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if let uri = SpotifyService.spotifyURI(type: "album", id: albumId),
                       UIApplication.shared.canOpenURL(uri) {
                        UIApplication.shared.open(uri)
                    } else if let webURL = SpotifyService.spotifyWebURL(type: "album", id: albumId) {
                        UIApplication.shared.open(webURL)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.circle")
                        .foregroundColor(.green)
                }
                .accessibilityLabel("Open in Spotify")
            }
        }
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
        .task {
            if !spotifyService.isAuthenticated {
                await spotifyService.authenticate()
            }
            await loadAlbumData()
            await loadBuddyRatings()
        }
        .onChange(of: ratingsManager.allRatings) { _, _ in
            updateBuddyRatings()
        }
    }
    
    // MARK: - Album Header
    
    private var albumHeader: some View {
        VStack(spacing: 16) {
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
            .padding(.horizontal, 16)
            
            // Album Name
            Text(album?.name ?? albumName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Release Year & Track Count
            HStack(spacing: 12) {
                if let year = album?.releaseYear {
                    Text(year)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                if let trackCount = album?.totalTracks {
                    Text("•")
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(trackCount) tracks")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.top, 20)
        .padding(.horizontal)
    }
    
    // MARK: - Rating Section
    
    private var ratingSection: some View {
        VStack(spacing: 20) {
            // Split rating display
            HStack(spacing: 40) {
                // User's Rating (Left side)
                if let userRating = getUserRating() {
                    VStack(spacing: 6) {
                        Text("you gave a")
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
                if let average = ratingsManager.getAverageRating(for: albumId) {
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
                .disabled(album == nil)
                
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
        let ratingId = UserRating.makeId(userId: userId, spotifyId: albumId)
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
        buddyRatings = ratingsManager.getBuddyRatings(for: albumId, buddyIds: buddyIds)
    }
    
    // MARK: - Artist Section
    
    private var artistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with column labels
            HStack {
                Text("artist")
                    .font(.title3)
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
            
            if let artists = album?.artists {
                ForEach(artists, id: \.id) { artist in
                    NavigationLink(destination: ArtistDetailView(
                        artistId: artist.id,
                        artistName: artist.name,
                        artistImageURL: nil
                    )) {
                        HStack(spacing: 12) {
                            Text(artist.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            RatingBadgeCompact(spotifyId: artist.id, ratingsManager: ratingsManager, userId: authManager.currentUser?.id)
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.03))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
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
                            userId: authManager.currentUser?.id
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
        .padding(.top, 16)
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
    }
}

// MARK: - Album Track Row View

struct AlbumTrackRowView: View {
    let track: SpotifyTrackSimple
    let albumImageURL: URL?
    let ratingsManager: RatingsManager
    let userId: String?
    
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
            RatingBadgeCompact(spotifyId: track.id, ratingsManager: ratingsManager, userId: userId)
            
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
