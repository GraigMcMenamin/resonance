//
//  ProfileView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import SwiftUI
import Combine

struct ProfileView: View {
    @EnvironmentObject var ratingsManager: RatingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var buddyManager: BuddyManager
    @StateObject private var viewModel = ProfileViewModel()
    @State private var selectedPickerType: TopItemType?
    
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
            .onChange(of: authManager.currentUser?.id) { oldValue, newValue in
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
                    await ratingsManager.loadUserRatings(userId: userId)
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
                    if let imageURLString = authManager.currentUser?.imageURL,
                       let imageURL = URL(string: imageURLString) {
                        AsyncImage(url: imageURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.width)
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
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 16)
            
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
            
            // Rating Count
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(ratingsManager.ratings.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Ratings")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                if let avgRating = ratingsManager.averageRating() {
                    Divider()
                        .frame(height: 30)
                        .background(Color.white.opacity(0.3))
                    
                    VStack(spacing: 4) {
                        Text("\(Int(avgRating))%")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("Avg. Rating")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            
            // Logout Button
            Button(action: {
                authManager.logout()
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Logout")
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.7))
                .cornerRadius(20)
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
        NavigationLink(destination: BuddiesListView(buddies: buddyManager.buddies, title: "My Buddies")) {
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
    @StateObject private var spotifyService = SpotifyService()
    
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
                        
                        TextField("Search \(itemType.displayName.lowercased())s", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundColor(.white)
                            .onChange(of: searchText) { oldValue, newValue in
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
            .navigationTitle("select top 3 \(itemType.displayName)s")
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
            await spotifyService.authenticate()
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
        case .artist: return "Artists"
        case .track: return "Songs"
        case .album: return "Albums"
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
