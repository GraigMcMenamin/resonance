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
    
    @State private var track: SpotifyTrack?
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
                        Task { await loadTrackData() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Song Header
                        songHeader
                        
                        // Rating Section
                        ratingSection
                        
                        // Artists Section
                        artistsSection
                        
                        // Album Section
                        albumSection
                        
                        // Track Info
                        trackInfoSection
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(trackName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    if let uri = SpotifyService.spotifyURI(type: "track", id: trackId),
                       UIApplication.shared.canOpenURL(uri) {
                        UIApplication.shared.open(uri)
                    } else if let webURL = SpotifyService.spotifyWebURL(type: "track", id: trackId) {
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
        .task {
            if !spotifyService.isAuthenticated {
                await spotifyService.authenticate()
            }
            await loadTrackData()
            await loadBuddyRatings()
        }
        .onChange(of: ratingsManager.allRatings) { _, _ in
            // Update buddy ratings when ratings change
            updateBuddyRatings()
        }
    }
    
    // MARK: - Song Header
    
    private var songHeader: some View {
        VStack(spacing: 16) {
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
            .padding(.horizontal, 16)
            
            // Song Name
            Text(track?.name ?? trackName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
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
                if let average = ratingsManager.getAverageRating(for: trackId) {
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
                    if let track = track {
                        selectedItem = .track(track)
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
                .disabled(track == nil)
                
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
    
    private var hasUserRating: Bool {
        getUserRating() != nil
    }
    
    private func getUserRating() -> UserRating? {
        guard let userId = authManager.currentUser?.id else { return nil }
        let ratingId = UserRating.makeId(userId: userId, spotifyId: trackId)
        return ratingsManager.getRating(for: ratingId)
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
        buddyRatings = ratingsManager.getBuddyRatings(for: trackId, buddyIds: buddyIds)
    }
    
    // MARK: - Artists Section
    
    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row with column labels
            HStack {
                Text(track?.artists.count ?? 1 > 1 ? "artists" : "artist")
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
            
            if let artists = track?.artists {
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
                        
                        RatingBadgeCompact(spotifyId: album.id, ratingsManager: ratingsManager, userId: authManager.currentUser?.id)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
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
                        
                        RatingBadgeCompact(spotifyId: albumId, ratingsManager: ratingsManager, userId: authManager.currentUser?.id)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Track Info Section
    
    private var trackInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let popularity = track?.popularity {
                HStack {
                    Text("Spotify Popularity:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(popularity)/100")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 16)
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
