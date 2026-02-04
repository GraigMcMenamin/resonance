//
//  SearchView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import SwiftUI

struct SearchView: View {
    @StateObject private var spotifyService = SpotifyService()
    @EnvironmentObject var ratingsManager: RatingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    
    @State private var searchText = ""
    @State private var selectedTab = 0
    @State private var artists: [SpotifyArtist] = []
    @State private var albums: [SpotifyAlbum] = []
    @State private var tracks: [SpotifyTrack] = []
    @State private var users: [AppUser] = []
    @State private var isLoading = false
    @State private var selectedItem: RatableItem?
    
    enum SearchTab: Int {
        case songs = 0
        case artists = 1
        case albums = 2
        case users = 3
        case all = 4
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                SearchBar(text: $searchText, onSearch: performSearch)
                    .padding()
                
                // Tabs
                Picker("Type", selection: $selectedTab) {
                    Text("songs").tag(0)
                    Text("artists").tag(1)
                    Text("albums").tag(2)
                    Text("users").tag(3)
                    Text("all").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Results
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    TabView(selection: $selectedTab) {
                        TrackListView(tracks: tracks, selectedItem: $selectedItem, ratingsManager: ratingsManager, userId: authManager.currentUser?.id)
                            .tag(0)
                        
                        ArtistListView(artists: artists, selectedItem: $selectedItem, ratingsManager: ratingsManager, userId: authManager.currentUser?.id)
                            .tag(1)
                        
                        AlbumListView(albums: albums, selectedItem: $selectedItem, ratingsManager: ratingsManager, userId: authManager.currentUser?.id)
                            .tag(2)
                        
                        UserListView(users: users, currentUserId: authManager.currentUser?.id)
                            .tag(3)
                        
                        AllResultsView(
                            artists: artists,
                            albums: albums,
                            tracks: tracks,
                            selectedItem: $selectedItem,
                            ratingsManager: ratingsManager,
                            userId: authManager.currentUser?.id
                        )
                        .tag(4)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("search music")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedItem) { item in
                RatingSheet(item: item, ratingsManager: ratingsManager)
                    .environmentObject(authManager)
                    .environmentObject(firebaseService)
            }
            .onChange(of: selectedTab) { oldValue, newValue in
                performSearch()
            }
            .task {
                await spotifyService.authenticate()
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isLoading = true
        
        Task {
            do {
                switch selectedTab {
                case 0: // Songs
                    tracks = try await spotifyService.searchTracks(query: searchText)
                case 1: // Artists
                    artists = try await spotifyService.searchArtists(query: searchText)
                case 2: // Albums
                    albums = try await spotifyService.searchAlbums(query: searchText)
                case 3: // Users
                    users = try await firebaseService.searchUsers(query: searchText)
                case 4: // All
                    async let artistsResult = spotifyService.searchArtists(query: searchText)
                    async let albumsResult = spotifyService.searchAlbums(query: searchText)
                    async let tracksResult = spotifyService.searchTracks(query: searchText)
                    
                    artists = try await artistsResult
                    albums = try await albumsResult
                    tracks = try await tracksResult
                default:
                    break
                }
            } catch {
                print("search failed: \(error)")
            }
            isLoading = false
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String
    let onSearch: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("search artists, albums, or songs...", text: $text)
                .textFieldStyle(.plain)
                .tint(.white)
                .onChange(of: text) { oldValue, newValue in
                    onSearch()
                }
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Artist List

struct ArtistListView: View {
    let artists: [SpotifyArtist]
    @Binding var selectedItem: RatableItem?
    let ratingsManager: RatingsManager
    let userId: String?
    
    var body: some View {
        List(artists) { artist in
            NavigationLink(destination: ArtistDetailView(
                artistId: artist.id,
                artistName: artist.name,
                artistImageURL: artist.imageURL
            )) {
                HStack(spacing: 12) {
                    CustomAsyncImage(url: artist.imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 60, height: 60)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        case .failure:
                            Image(systemName: "music.mic")
                                .font(.title)
                                .foregroundColor(.gray)
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(Circle())
                        @unknown default:
                            Color.gray
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artist.name)
                            .font(.headline)
                        
                        if let genres = artist.genres?.prefix(2) {
                            Text(genres.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    RatingBadgeCompact(
                        spotifyId: artist.id,
                        ratingsManager: ratingsManager,
                        userId: userId
                    )
                }
            }
            .swipeActions(edge: .trailing) {
                Button {
                    selectedItem = .artist(artist)
                } label: {
                    Label("Rate", systemImage: "star.fill")
                }
                .tint(.orange)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Album List

struct AlbumListView: View {
    let albums: [SpotifyAlbum]
    @Binding var selectedItem: RatableItem?
    let ratingsManager: RatingsManager
    let userId: String?
    
    var body: some View {
        List(albums) { album in
            NavigationLink(destination: AlbumDetailView(
                albumId: album.id,
                albumName: album.name,
                artistName: album.artistNames,
                imageURL: album.imageURL
            )) {
                HStack(spacing: 12) {
                    CustomAsyncImage(url: album.imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 60, height: 60)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                        case .failure:
                            Image(systemName: "square.stack")
                                .font(.title)
                                .foregroundColor(.gray)
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        @unknown default:
                            Color.gray
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.name)
                            .font(.headline)
                        
                        Text(album.artistNames)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let releaseDate = album.releaseDate {
                            Text(String(releaseDate.prefix(4)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    RatingBadgeCompact(
                        spotifyId: album.id,
                        ratingsManager: ratingsManager,
                        userId: userId
                    )
                }
            }
            .swipeActions(edge: .trailing) {
                Button {
                    selectedItem = .album(album)
                } label: {
                    Label("Rate", systemImage: "star.fill")
                }
                .tint(.orange)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Track List

struct TrackListView: View {
    let tracks: [SpotifyTrack]
    @Binding var selectedItem: RatableItem?
    let ratingsManager: RatingsManager
    let userId: String?
    
    var body: some View {
        List(tracks) { track in
            NavigationLink(destination: SongDetailView(
                trackId: track.id,
                trackName: track.name,
                artistName: track.artistNames,
                albumName: track.album?.name,
                albumId: track.album?.id,
                imageURL: track.imageURL
            )) {
                HStack(spacing: 12) {
                    CustomAsyncImage(url: track.imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 60, height: 60)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                        case .failure:
                            Image(systemName: "music.note")
                                .font(.title)
                                .foregroundColor(.gray)
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(8)
                        @unknown default:
                            Color.gray
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name)
                            .font(.headline)
                        
                        Text(track.artistNames)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let album = track.album {
                            Text(album.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    RatingBadgeCompact(
                        spotifyId: track.id,
                        ratingsManager: ratingsManager,
                        userId: userId
                    )
                }
            }
            .swipeActions(edge: .trailing) {
                Button {
                    selectedItem = .track(track)
                } label: {
                    Label("Rate", systemImage: "star.fill")
                }
                .tint(.orange)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - All Results View

struct AllResultsView: View {
    let artists: [SpotifyArtist]
    let albums: [SpotifyAlbum]
    let tracks: [SpotifyTrack]
    @Binding var selectedItem: RatableItem?
    let ratingsManager: RatingsManager
    let userId: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                tracksSection
                artistsSection
                albumsSection
                emptyStateView
            }
            .padding(.vertical)
        }
    }
    
    @ViewBuilder
    private var artistsSection: some View {
        if !artists.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "artists")
                ForEach(Array(artists.prefix(3))) { artist in
                    artistRow(artist: artist)
                }
            }
        }
    }
    
    @ViewBuilder
    private var albumsSection: some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "albums")
                ForEach(Array(albums.prefix(3))) { album in
                    albumRow(album: album)
                }
            }
        }
    }
    
    @ViewBuilder
    private var tracksSection: some View {
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "songs")
                ForEach(Array(tracks.prefix(3))) { track in
                    trackRow(track: track)
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        if artists.isEmpty && albums.isEmpty && tracks.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("try searching for songs, artists, albums, or your friends")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
    
    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.bold)
            .padding(.horizontal)
    }
    
    private func artistRow(artist: SpotifyArtist) -> some View {
        NavigationLink(destination: ArtistDetailView(
            artistId: artist.id,
            artistName: artist.name,
            artistImageURL: artist.imageURL
        )) {
            HStack(spacing: 12) {
                artistImage(artist: artist)
                artistInfo(artist: artist)
                Spacer()
                RatingBadgeCompact(spotifyId: artist.id, ratingsManager: ratingsManager, userId: userId)
            }
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
    
    private func artistImage(artist: SpotifyArtist) -> some View {
        CustomAsyncImage(url: artist.imageURL) { phase in
            Group {
                switch phase {
                case .empty:
                    ProgressView().frame(width: 60, height: 60)
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "music.mic").font(.title).foregroundColor(.gray).frame(width: 60, height: 60).background(Color.gray.opacity(0.2))
                @unknown default:
                    Color.gray.frame(width: 60, height: 60)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
        }
    }
    
    private func artistInfo(artist: SpotifyArtist) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(artist.name).font(.headline)
            if let genres = artist.genres?.prefix(2) {
                Text(genres.joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
            }
        }
    }
    
    private func albumRow(album: SpotifyAlbum) -> some View {
        NavigationLink(destination: AlbumDetailView(
            albumId: album.id,
            albumName: album.name,
            artistName: album.artistNames,
            imageURL: album.imageURL
        )) {
            HStack(spacing: 12) {
                albumImage(album: album)
                albumInfo(album: album)
                Spacer()
                RatingBadgeCompact(spotifyId: album.id, ratingsManager: ratingsManager, userId: userId)
            }
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
    
    private func albumImage(album: SpotifyAlbum) -> some View {
        CustomAsyncImage(url: album.imageURL) { phase in
            Group {
                switch phase {
                case .empty:
                    ProgressView().frame(width: 60, height: 60)
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "opticaldisc").font(.title).foregroundColor(.gray).frame(width: 60, height: 60).background(Color.gray.opacity(0.2))
                @unknown default:
                    Color.gray.frame(width: 60, height: 60)
                }
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)
        }
    }
    
    private func albumInfo(album: SpotifyAlbum) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(album.name).font(.headline)
            Text(album.artistNames).font(.subheadline).foregroundColor(.secondary)
            if let releaseYear = album.releaseYear {
                Text(releaseYear).font(.caption).foregroundColor(.secondary)
            }
        }
    }
    
    private func trackRow(track: SpotifyTrack) -> some View {
        NavigationLink(destination: SongDetailView(
            trackId: track.id,
            trackName: track.name,
            artistName: track.artistNames,
            albumName: track.album?.name,
            albumId: track.album?.id,
            imageURL: track.imageURL
        )) {
            HStack(spacing: 12) {
                trackImage(track: track)
                trackInfo(track: track)
                Spacer()
                trackRating(track: track)
            }
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
    
    private func trackImage(track: SpotifyTrack) -> some View {
        CustomAsyncImage(url: track.album?.imageURL) { phase in
            Group {
                switch phase {
                case .empty:
                    ProgressView().frame(width: 60, height: 60)
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "music.note").font(.title).foregroundColor(.gray).frame(width: 60, height: 60).background(Color.gray.opacity(0.2))
                @unknown default:
                    Color.gray.frame(width: 60, height: 60)
                }
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)
        }
    }
    
    private func trackInfo(track: SpotifyTrack) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.name).font(.headline)
            Text(track.artistNames).font(.subheadline).foregroundColor(.secondary)
            if let album = track.album {
                Text(album.name).font(.caption).foregroundColor(.secondary)
            }
        }
    }
    
    private func trackRating(track: SpotifyTrack) -> some View {
        RatingBadgeCompact(spotifyId: track.id, ratingsManager: ratingsManager, userId: userId)
    }
}

// MARK: - User List

struct UserListView: View {
    let users: [AppUser]
    let currentUserId: String?
    
    var filteredUsers: [AppUser] {
        users.filter { $0.id != currentUserId }
    }
    
    var body: some View {
        if filteredUsers.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                Text("no users found")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("try searching by username")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            List(filteredUsers) { user in
                NavigationLink(destination: OtherUserProfileView(user: user)) {
                    HStack(spacing: 12) {
                        // Profile Image
                        if let imageURLString = user.imageURL, let imageURL = URL(string: imageURLString) {
                            AsyncImage(url: imageURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.white.opacity(0.5))
                                    )
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.white.opacity(0.5))
                                )
                        }
                        
                        // User Info
                        VStack(alignment: .leading, spacing: 4) {
                            if let username = user.username {
                                Text("@\(username)")
                                    .font(.headline)
                            }
                            
                            Text(user.displayName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Ratable Item Enum

enum RatableItem: Identifiable {
    case artist(SpotifyArtist)
    case album(SpotifyAlbum)
    case track(SpotifyTrack)
    
    var id: String {
        switch self {
        case .artist(let artist): return artist.id
        case .album(let album): return album.id
        case .track(let track): return track.id
        }
    }
}

// MARK: - Custom AsyncImage with SSL handling

struct CustomAsyncImage<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content
    
    @State private var phase: AsyncImagePhase = .empty
    
    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }
    
    var body: some View {
        content(phase)
            .task {
                await loadImage()
            }
    }
    
    private func loadImage() async {
        guard let url = url else {
            phase = .failure(URLError(.badURL))
            return
        }
        
        do {
            let (data, _) = try await CustomImageLoader.shared.session.data(from: url)
            #if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                phase = .success(Image(uiImage: uiImage))
            } else {
                phase = .failure(URLError(.cannotDecodeContentData))
            }
            #elseif canImport(AppKit)
            if let nsImage = NSImage(data: data) {
                phase = .success(Image(nsImage: nsImage))
            } else {
                phase = .failure(URLError(.cannotDecodeContentData))
            }
            #endif
        } catch {
            phase = .failure(error)
        }
    }
}

#Preview {
    SearchView()
        .environmentObject(RatingsManager(firebaseService: FirebaseService()))
        .environmentObject(FirebaseService())
        .environmentObject(AuthenticationManager())
}
