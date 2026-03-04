//
//  ProfileView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import SwiftUI
import Combine
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var ratingsManager: RatingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var buddyManager: BuddyManager
    @EnvironmentObject var spotifyService: SpotifyService
    @StateObject private var viewModel = ProfileViewModel()
    @State private var selectedPickerType: TopItemType?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingImage = false
    @State private var showImageOptions = false
    @State private var showRemoveConfirmation = false
    @State private var showPhotoPicker = false
    @State private var imageToCrop: UIImage?
    @State private var isEditingLyric = false
    @State private var lyricText: String = ""
    @State private var isSavingLyric = false
    @State private var showLyricSongPicker = false
    @State private var lyricSongIdDraft: String? = nil
    @State private var lyricSongNameDraft: String? = nil
    @State private var lyricSongArtistDraft: String? = nil
    @State private var lyricSongImageURLDraft: String? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // User Profile Header
                        userProfileHeader()
                        
                        // Only show sections for authenticated users
                        if !authManager.isGuestMode {
                            // Buddy Requests Section (if any pending)
                            if !buddyManager.pendingRequests.isEmpty {
                                buddyRequestsSection()
                            }
                            
                            // Buddies Section
                            buddiesSection()
                            
                            // Top 3 Artists
                            topItemsSection(
                                title: "top 3 artists",
                                items: viewModel.topArtists,
                                type: .artist
                            )
                            
                            // Top 3 Songs
                            topItemsSection(
                                title: "top 3 songs",
                                items: viewModel.topTracks,
                                type: .track
                            )
                            
                            // Top 3 Albums
                            topItemsSection(
                                title: "top 3 albums",
                                items: viewModel.topAlbums,
                                type: .album
                            )
                        }
                        
                        // Ratings Section
                        ratingsSection()
                    }
                    .padding()
                }
            }
            .navigationTitle("profile")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedPickerType) { type in
                TopItemPicker(viewModel: viewModel, itemType: type)
                    .environmentObject(spotifyService)
            }
            .sheet(isPresented: $showLyricSongPicker) {
                LyricSongPicker(
                    selectedSongId: $lyricSongIdDraft,
                    selectedSongName: $lyricSongNameDraft,
                    selectedArtistName: $lyricSongArtistDraft,
                    selectedSongImageURL: $lyricSongImageURLDraft
                )
                .environmentObject(spotifyService)
            }
            .fullScreenCover(item: Binding(
                get: { imageToCrop.map { IdentifiableImage(image: $0) } },
                set: { if $0 == nil { imageToCrop = nil } }
            )) { identifiable in
                ImageCropperView(
                    image: identifiable.image,
                    onCropped: { croppedImage in
                        imageToCrop = nil
                        Task {
                            await uploadCroppedImage(croppedImage)
                        }
                    },
                    onCancel: {
                        imageToCrop = nil
                    }
                )
            }
            .onAppear {
                viewModel.initialize(firebaseService: firebaseService)
                viewModel.setUserId(authManager.currentUser?.id)
                buddyManager.initialize(firebaseService: firebaseService)
                buddyManager.setUserId(authManager.currentUser?.id)
                
                // Load user ratings if authenticated
                if let userId = authManager.currentUser?.id, !authManager.isGuestMode {
                    Task {
                        await ratingsManager.loadUserRatings(userId: userId)
                    }
                }
            }
            .onChange(of: authManager.currentUser?.id) { newValue in
                viewModel.setUserId(newValue)
                buddyManager.setUserId(newValue)
                
                // Load ratings when user changes
                if let userId = newValue, !authManager.isGuestMode {
                    Task {
                        await ratingsManager.loadUserRatings(userId: userId)
                    }
                }
            }
            .refreshable {
                if let userId = authManager.currentUser?.id {
                    await buddyManager.refresh()
                    await ratingsManager.refreshUserRatings(userId: userId)
                }
            }
        }
    }
    
    @ViewBuilder
    private func userProfileHeader() -> some View {
        VStack(spacing: 16) {
            // Guest Mode Check
            if authManager.isGuestMode {
                // Guest Profile
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.5))
                    )
                
                Text("Guest User")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Sign in to save ratings and customize your profile")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Sign In Button
                Button(action: {
                    authManager.exitGuestMode()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note")
                        Text("Sign in with Spotify")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.11, green: 0.73, blue: 0.33))
                    .cornerRadius(25)
                }
                .padding(.top, 8)
            } else {
                // Authenticated User Profile
                // Profile Image - full width square like album covers
                GeometryReader { geometry in
                    ZStack(alignment: .bottomTrailing) {
                        if let imageURLString = authManager.currentUser?.displayImageURL,
                           let imageURL = URL(string: imageURLString) {
                            AsyncImage(url: imageURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width, height: geometry.size.width)
                                    .clipped()
                                    .cornerRadius(12)
                                    .shadow(color: .black.opacity(0.3), radius: 15)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: geometry.size.width, height: geometry.size.width)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 60))
                                            .foregroundColor(.white.opacity(0.5))
                                    )
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: geometry.size.width, height: geometry.size.width)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        }
                        
                        // Upload overlay
                        if isUploadingImage {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.5))
                                .frame(width: geometry.size.width, height: geometry.size.width)
                                .overlay(
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(1.5)
                                )
                        }
                        
                        // Camera button overlay
                        Button(action: {
                            if authManager.currentUser?.customImageURL != nil {
                                showImageOptions = true
                            } else {
                                showPhotoPicker = true
                            }
                        }) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color(red: 0.15, green: 0.08, blue: 0.18).opacity(0.9))
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding(12)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 16)
                .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
                .confirmationDialog("Profile Picture", isPresented: $showImageOptions, titleVisibility: .visible) {
                    Button("Choose from Library") {
                        showPhotoPicker = true
                    }
                    if authManager.currentUser?.customImageURL != nil {
                        Button("Remove Custom Photo", role: .destructive) {
                            showRemoveConfirmation = true
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .alert("Remove Custom Photo?", isPresented: $showRemoveConfirmation) {
                    Button("Remove", role: .destructive) {
                        Task {
                            await removeCustomImage()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will revert to your Spotify profile picture.")
                }
                .onChange(of: selectedPhotoItem) { newItem in
                    if let newItem = newItem {
                        Task {
                            await loadImageForCropping(newItem)
                            selectedPhotoItem = nil
                        }
                    }
                }
            
            // Username
            if let username = authManager.currentUser?.username {
                Text("@\(username)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            } else {
                Text("User")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // Favorite Lyric
            if isEditingLyric {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("type a favorite lyric...", text: $lyricText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.white)
                        .lineLimit(2...5)
                        .onChange(of: lyricText) { newValue in
                            if newValue.count > 200 {
                                lyricText = String(newValue.prefix(200))
                            }
                        }
                    
                    // Linked Song Row
                    Button(action: { showLyricSongPicker = true }) {
                        HStack(spacing: 10) {
                            if let urlStr = lyricSongImageURLDraft, let url = URL(string: urlStr) {
                                AsyncImage(url: url) { img in
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 36, height: 36)
                                .cornerRadius(4)
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 36, height: 36)
                                    .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.4)).font(.caption))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                if let name = lyricSongNameDraft {
                                    Text(name)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    if let artist = lyricSongArtistDraft {
                                        Text(artist)
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.6))
                                            .lineLimit(1)
                                    }
                                } else {
                                    Text("link the song")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            }
                            
                            Spacer()
                            
                            if lyricSongIdDraft != nil {
                                Button(action: {
                                    lyricSongIdDraft = nil
                                    lyricSongNameDraft = nil
                                    lyricSongArtistDraft = nil
                                    lyricSongImageURLDraft = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white.opacity(0.4))
                                        .font(.caption)
                                }
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.3))
                                    .font(.caption)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    HStack(spacing: 12) {
                        Text("\(lyricText.count)/200")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                        
                        Spacer()
                        
                        Button("Cancel") {
                            isEditingLyric = false
                            lyricText = authManager.currentUser?.favoriteLyric ?? ""
                            lyricSongIdDraft = authManager.currentUser?.favoriteLyricSongId
                            lyricSongNameDraft = authManager.currentUser?.favoriteLyricSongName
                            lyricSongArtistDraft = authManager.currentUser?.favoriteLyricArtistName
                            lyricSongImageURLDraft = authManager.currentUser?.favoriteLyricSongImageURL
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        
                        Button(action: {
                            guard let userId = authManager.currentUser?.id else { return }
                            isSavingLyric = true
                            Task {
                                do {
                                    let trimmed = lyricText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    try await firebaseService.updateFavoriteLyric(
                                        lyric: trimmed.isEmpty ? nil : trimmed,
                                        songId: lyricSongIdDraft,
                                        songName: lyricSongNameDraft,
                                        artistName: lyricSongArtistDraft,
                                        songImageURL: lyricSongImageURLDraft,
                                        for: userId
                                    )
                                    authManager.currentUser?.favoriteLyric = trimmed.isEmpty ? nil : trimmed
                                    authManager.currentUser?.favoriteLyricSongId = lyricSongIdDraft
                                    authManager.currentUser?.favoriteLyricSongName = lyricSongNameDraft
                                    authManager.currentUser?.favoriteLyricArtistName = lyricSongArtistDraft
                                    authManager.currentUser?.favoriteLyricSongImageURL = lyricSongImageURLDraft
                                } catch {
                                    print("[ProfileView] Failed to save lyric: \(error)")
                                }
                                isSavingLyric = false
                                isEditingLyric = false
                            }
                        }) {
                            if isSavingLyric {
                                ProgressView().scaleEffect(0.7).tint(.white)
                            } else {
                                Text("Save")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(red: 0.11, green: 0.73, blue: 0.33))
                            }
                        }
                        .disabled(isSavingLyric)
                    }
                }
                .padding(.horizontal, 4)
            } else {
                Button(action: {
                    lyricText = authManager.currentUser?.favoriteLyric ?? ""
                    lyricSongIdDraft = authManager.currentUser?.favoriteLyricSongId
                    lyricSongNameDraft = authManager.currentUser?.favoriteLyricSongName
                    lyricSongArtistDraft = authManager.currentUser?.favoriteLyricArtistName
                    lyricSongImageURLDraft = authManager.currentUser?.favoriteLyricSongImageURL
                    isEditingLyric = true
                }) {
                    VStack(spacing: 8) {
                        if let lyric = authManager.currentUser?.favoriteLyric, !lyric.isEmpty {
                            Text("\"\(lyric)\"")
                                .font(.subheadline)
                                .italic()
                                .foregroundColor(.white.opacity(0.85))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 4)
                            
                            // Linked song chip
                            if let songId = authManager.currentUser?.favoriteLyricSongId,
                               let songName = authManager.currentUser?.favoriteLyricSongName {
                                NavigationLink(destination: SongDetailView(
                                    trackId: songId,
                                    trackName: songName,
                                    artistName: authManager.currentUser?.favoriteLyricArtistName ?? "",
                                    albumName: nil,
                                    albumId: nil,
                                    imageURL: authManager.currentUser?.favoriteLyricSongImageURL.flatMap { URL(string: $0) }
                                )) {
                                    HStack(spacing: 8) {
                                        if let urlStr = authManager.currentUser?.favoriteLyricSongImageURL,
                                           let url = URL(string: urlStr) {
                                            AsyncImage(url: url) { img in
                                                img.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.3))
                                            }
                                            .frame(width: 24, height: 24)
                                            .cornerRadius(3)
                                        }
                                        Text(songName)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))
                                            .lineLimit(1)
                                        if let artist = authManager.currentUser?.favoriteLyricArtistName {
                                            Text("— \(artist)")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.4))
                                                .lineLimit(1)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.25))
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Text("+ add a favorite lyric")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.35))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            
            // Ratings count
            HStack(spacing: 4) {
                Text("\(ratingsManager.ratings.count)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text("ratings")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Logout Button
            Button(action: {
                authManager.logout()
            }) {
                Text("logout")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }
            } // End of authenticated user else block
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func topItemsSection(title: String, items: [TopItem], type: TopItemType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    selectedPickerType = type
                }) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.title3)
                }
            }
            
            if items.isEmpty {
                emptyStateView(type: type)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        topItemRow(item: item, rank: index + 1, type: type)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func topItemRow(item: TopItem, rank: Int, type: TopItemType) -> some View {
        NavigationLink(destination: topItemDestinationView(for: item, type: type)) {
            HStack(spacing: 10) {
                // Rank badge
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 28, height: 28)
                    
                    Text("\(rank)")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                
                // Artwork
                if let imageURL = item.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .clipShape(type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    // Don't show subtitle (genre) for artists
                    if type != .artist, let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // User's rating percentage
                if let userId = authManager.currentUser?.id {
                    let ratingId = UserRating.makeId(userId: userId, spotifyId: item.id)
                    if let rating = ratingsManager.getRating(for: ratingId) {
                        Text("\(rating.percentage)%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(10)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func topItemDestinationView(for item: TopItem, type: TopItemType) -> some View {
        switch type {
        case .artist:
            ArtistDetailView(
                artistId: item.id,
                artistName: item.name,
                artistImageURL: item.imageURL
            )
        case .album:
            AlbumDetailView(
                albumId: item.id,
                albumName: item.name,
                artistName: item.subtitle ?? "",
                imageURL: item.imageURL
            )
        case .track:
            SongDetailView(
                trackId: item.id,
                trackName: item.name,
                artistName: item.subtitle ?? "",
                albumName: nil,
                albumId: nil,
                imageURL: item.imageURL
            )
        }
    }
    
    // MARK: - Buddy Request Section
    
    @ViewBuilder
    private func buddyRequestsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("buddy requests")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(buddyManager.pendingRequests.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .cornerRadius(10)
            }
            
            VStack(spacing: 12) {
                ForEach(buddyManager.pendingRequests) { request in
                    buddyRequestRow(request: request)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func buddyRequestRow(request: BuddyRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Profile Image
                if let imageURLString = request.fromImageURL, let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("From @\(request.fromUsername)")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Will you be my buddy?")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
            }
            
            // Accept/Reject buttons
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await buddyManager.acceptRequest(request)
                    }
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Yes")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(8)
                }
                
                Button(action: {
                    Task {
                        await buddyManager.rejectRequest(request)
                    }
                }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("No")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.7))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
    
    // MARK: - Buddies Section
    
    @ViewBuilder
    private func buddiesSection() -> some View {
        NavigationLink(destination: BuddiesListView(buddies: buddyManager.buddies, title: "My Buddies", allowRemove: true)) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Text("buddies")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(buddyManager.buddies.count)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func emptyStateView(type: TopItemType) -> some View {
        VStack(spacing: 8) {
            Image(systemName: type == .artist ? "person.3.fill" : type == .track ? "music.note" : "square.stack.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            
            Text("Tap the edit button to add your top \(type.displayName.lowercased())s")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    @ViewBuilder
    private func ratingsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("recent reviews")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if ratingsManager.ratings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("No ratings yet")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // Recent ratings
                VStack(spacing: 12) {
                    ForEach(ratingsManager.allRatingsSorted.prefix(10)) { rating in
                        NavigationLink(destination: ratingDestinationView(for: rating)) {
                            ratingRow(rating: rating)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func ratingDestinationView(for rating: UserRating) -> some View {
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
    
    @ViewBuilder
    private func ratingRow(rating: UserRating) -> some View {
        HStack(spacing: 10) {
            // Artwork
            if let imageURLString = rating.imageURL, let imageURL = URL(string: imageURLString) {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 45, height: 45)
                .cornerRadius(6)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 45, height: 45)
                    .cornerRadius(6)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(rating.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let artistName = rating.artistName {
                    Text(artistName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                // Rating
                Text("\(rating.percentage)%")
                    .font(.headline)
                    .foregroundColor(.white)
                
                // Rating bar
                RatingBar(percentage: Double(rating.percentage))
                    .frame(width: 70, height: 8)
            }
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
    
    // MARK: - Profile Image Helpers
    
    private func loadImageForCropping(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                print("[ProfileView] Failed to load image data")
                return
            }
            imageToCrop = image
        } catch {
            print("[ProfileView] Failed to load image: \(error)")
        }
    }
    
    private func uploadCroppedImage(_ image: UIImage) async {
        isUploadingImage = true
        defer { isUploadingImage = false }
        
        guard let userId = authManager.currentUser?.id else { return }
        
        do {
            let downloadURL = try await firebaseService.uploadProfileImage(image, userId: userId)
            authManager.currentUser?.customImageURL = downloadURL
            print("[ProfileView] Profile image updated successfully")
        } catch {
            print("[ProfileView] Failed to upload profile image: \(error)")
        }
    }
    
    private func removeCustomImage() async {
        isUploadingImage = true
        defer { isUploadingImage = false }
        
        guard let userId = authManager.currentUser?.id else { return }
        
        do {
            try await firebaseService.removeCustomProfileImage(userId: userId)
            authManager.currentUser?.customImageURL = nil
            print("[ProfileView] Custom profile image removed")
        } catch {
            print("[ProfileView] Failed to remove custom image: \(error)")
        }
    }
}

// MARK: - Top Item Picker

struct TopItemPicker: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: ProfileViewModel
    let itemType: TopItemType
    
    @State private var searchText = ""
    @State private var searchResults: [TopItem] = []
    @State private var isSearching = false
    @State private var isAuthenticating = true
    @EnvironmentObject var spotifyService: SpotifyService
    
    var selectedItems: [TopItem] {
        switch itemType {
        case .artist: return viewModel.topArtists
        case .track: return viewModel.topTracks
        case .album: return viewModel.topAlbums
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.5))
                        
                        TextField("Search \(itemType.displayName.lowercased())", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .onChange(of: searchText) { _ in
                                Task {
                                    await performSearch()
                                }
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                searchResults = []
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .padding()
                    
                    // Selected items
                    if !selectedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected (\(selectedItems.count)/3)")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(selectedItems) { item in
                                        selectedItemChip(item: item)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom)
                    }
                    
                    // Search results
                    if isAuthenticating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding()
                        Spacer()
                    } else if isSearching {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding()
                        Spacer()
                    } else if searchResults.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.3))
                            Text(searchText.isEmpty ? "Start typing to search" : "No results found")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(searchResults) { item in
                                    searchResultRow(item: item)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("select top 3 \(itemType.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .task {
            if !spotifyService.isAuthenticated {
                await spotifyService.authenticate()
            }
            isAuthenticating = false
        }
    }
    
    @ViewBuilder
    private func selectedItemChip(item: TopItem) -> some View {
        HStack(spacing: 8) {
            if let imageURL = item.imageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 40, height: 40)
                .cornerRadius(6)
            }
            
            Text(item.name)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Button(action: {
                removeItem(item)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.2))
        .cornerRadius(20)
    }
    
    @ViewBuilder
    private func searchResultRow(item: TopItem) -> some View {
        let isSelected = selectedItems.contains(where: { $0.id == item.id })
        
        Button(action: {
            if isSelected {
                removeItem(item)
            } else {
                addItem(item)
            }
        }) {
            HStack(spacing: 12) {
                // Artwork
                if let imageURL = item.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .white.opacity(0.3))
                    .font(.title3)
            }
            .padding()
            .background(Color.white.opacity(isSelected ? 0.1 : 0.03))
            .cornerRadius(10)
        }
        .disabled(isSelected ? false : selectedItems.count >= 3)
        .opacity(selectedItems.count >= 3 && !isSelected ? 0.5 : 1.0)
    }
    
    private func addItem(_ item: TopItem) {
        guard selectedItems.count < 3 else { return }
        viewModel.addTopItem(item, type: itemType)
    }
    
    private func removeItem(_ item: TopItem) {
        viewModel.removeTopItem(item, type: itemType)
    }
    
    private func performSearch() async {
        guard !searchText.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            switch itemType {
            case .artist:
                let artists = try await spotifyService.searchArtists(query: searchText)
                searchResults = artists.map { TopItem(from: $0) }
            case .track:
                let tracks = try await spotifyService.searchTracks(query: searchText)
                searchResults = tracks.map { TopItem(from: $0) }
            case .album:
                let albums = try await spotifyService.searchAlbums(query: searchText)
                searchResults = albums.map { TopItem(from: $0) }
            }
        } catch {
            print("Search failed: \(error)")
            searchResults = []
        }
    }
}

// MARK: - Lyric Song Picker

struct LyricSongPicker: View {
    @Binding var selectedSongId: String?
    @Binding var selectedSongName: String?
    @Binding var selectedArtistName: String?
    @Binding var selectedSongImageURL: String?
    
    @EnvironmentObject var spotifyService: SpotifyService
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [SpotifyTrack] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.5))
                        
                        TextField("search for a song...", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .onChange(of: searchText) { _ in
                                Task { await performSearch() }
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = ""; searchResults = [] }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .padding()
                    
                    if isSearching {
                        ProgressView().tint(.white).padding()
                        Spacer()
                    } else if searchResults.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.25))
                            Text(searchText.isEmpty ? "search for the song your lyric is from" : "no results")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(searchResults) { track in
                                    Button(action: {
                                        selectedSongId = track.id
                                        selectedSongName = track.name
                                        selectedArtistName = track.artists.first?.name
                                        selectedSongImageURL = track.album?.images?.first?.url
                                        dismiss()
                                    }) {
                                        HStack(spacing: 12) {
                                            AsyncImage(url: track.imageURL) { img in
                                                img.resizable().aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.3))
                                            }
                                            .frame(width: 44, height: 44)
                                            .cornerRadius(4)
                                            
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(track.name)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                if let artist = track.artists.first?.name {
                                                    Text(artist)
                                                        .font(.caption)
                                                        .foregroundColor(.white.opacity(0.6))
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().background(Color.white.opacity(0.08))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("link a song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.white)
                }
            }
        }
    }
    
    private func performSearch() async {
        guard !searchText.isEmpty else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await spotifyService.searchTracks(query: searchText)
        } catch {
            print("[LyricSongPicker] Search failed: \(error)")
            searchResults = []
        }
    }
}

// MARK: - View Model

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var topArtists: [TopItem] = []
    @Published var topTracks: [TopItem] = []
    @Published var topAlbums: [TopItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var firebaseService: FirebaseService!
    private var currentUserId: String?
    
    nonisolated init() {}
    
    func initialize(firebaseService: FirebaseService) {
        self.firebaseService = firebaseService
    }
    
    func setUserId(_ userId: String?) {
        self.currentUserId = userId
        if let userId = userId {
            Task {
                await loadTopItems(for: userId)
            }
        } else {
            // Clear items when user logs out
            topArtists = []
            topTracks = []
            topAlbums = []
        }
    }
    
    func addTopItem(_ item: TopItem, type: TopItemType) {
        guard let userId = currentUserId else {
            errorMessage = "You must be signed in to save top items"
            return
        }
        
        switch type {
        case .artist:
            if topArtists.count < 3 && !topArtists.contains(where: { $0.id == item.id }) {
                topArtists.append(item)
            }
        case .track:
            if topTracks.count < 3 && !topTracks.contains(where: { $0.id == item.id }) {
                topTracks.append(item)
            }
        case .album:
            if topAlbums.count < 3 && !topAlbums.contains(where: { $0.id == item.id }) {
                topAlbums.append(item)
            }
        }
        
        Task {
            await saveTopItems(for: userId)
        }
    }
    
    func removeTopItem(_ item: TopItem, type: TopItemType) {
        guard let userId = currentUserId else {
            errorMessage = "You must be signed in to modify top items"
            return
        }
        
        switch type {
        case .artist:
            topArtists.removeAll { $0.id == item.id }
        case .track:
            topTracks.removeAll { $0.id == item.id }
        case .album:
            topAlbums.removeAll { $0.id == item.id }
        }
        
        Task {
            await saveTopItems(for: userId)
        }
    }
    
    private func saveTopItems(for userId: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await firebaseService.saveUserTopItems(
                userId: userId,
                topArtists: topArtists,
                topTracks: topTracks,
                topAlbums: topAlbums
            )
        } catch {
            errorMessage = "Failed to save top items: \(error.localizedDescription)"
            print("Error saving top items: \(error)")
        }
    }
    
    private func loadTopItems(for userId: String) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            if let topItems = try await firebaseService.getUserTopItems(userId: userId) {
                topArtists = topItems.topArtists
                topTracks = topItems.topTracks
                topAlbums = topItems.topAlbums
            }
        } catch {
            errorMessage = "Failed to load top items: \(error.localizedDescription)"
            print("Error loading top items: \(error)")
        }
    }
}

// MARK: - Models

/// Wrapper to make UIImage work with .fullScreenCover(item:)
struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum TopItemType: Identifiable {
    case artist, track, album
    
    var id: String {
        switch self {
        case .artist: return "artist"
        case .track: return "track"
        case .album: return "album"
        }
    }
    
    var displayName: String {
        switch self {
        case .artist: return "artists"
        case .track: return "songs"
        case .album: return "albums"
        }
    }
}

#Preview {
    let firebaseService = FirebaseService()
    return ProfileView()
        .environmentObject(firebaseService)
        .environmentObject(RatingsManager(firebaseService: firebaseService))
        .environmentObject(AuthenticationManager())
        .environmentObject(BuddyManager())
}
