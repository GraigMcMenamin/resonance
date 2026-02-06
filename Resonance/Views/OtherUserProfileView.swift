//
//  OtherUserProfileView.swift
//  Resonance
//
//  Created by Claude on 1/22/26.
//

import SwiftUI
import Combine
import FirebaseFirestore

struct OtherUserProfileView: View {
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var viewModel = OtherUserProfileViewModel()
    @State private var buddyStatus: FirebaseService.BuddyStatus = .notBuddies
    @State private var isLoadingBuddyStatus = true
    @State private var isSendingRequest = false
    
    let user: AppUser
    
    var body: some View {
        ZStack {
            Color(red: 0.15, green: 0.08, blue: 0.18)
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // User Profile Header
                        userProfileHeader()
                        
                        // Buddy Button
                        buddyActionSection()
                        
                        // Buddies Section
                        buddiesSection()
                        
                        // Top 3 Artists
                        if !viewModel.topArtists.isEmpty {
                            topItemsSection(
                                title: "top 3 artists",
                                items: viewModel.topArtists,
                                type: .artist
                            )
                        }
                        
                        // Top 3 Songs
                        if !viewModel.topTracks.isEmpty {
                            topItemsSection(
                                title: "top 3 songs",
                                items: viewModel.topTracks,
                                type: .track
                            )
                        }
                        
                        // Top 3 Albums
                        if !viewModel.topAlbums.isEmpty {
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
        }
        .navigationTitle(user.username.map { "@\($0)" } ?? "User")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            print("DEBUG OtherUserProfileView: user.id = \(user.id)")
            print("DEBUG OtherUserProfileView: user.firebaseUID = \(user.firebaseUID)")
            print("DEBUG OtherUserProfileView: user.spotifyId = \(user.spotifyId ?? "nil")")
            viewModel.initialize(firebaseService: firebaseService)
            viewModel.loadUserData(userId: user.id)
            
            // Check buddy status
            Task {
                await loadBuddyStatus()
            }
        }
    }
    
    private func loadBuddyStatus() async {
        isLoadingBuddyStatus = true
        do {
            buddyStatus = try await firebaseService.checkBuddyStatus(
                userId: authManager.currentUser?.id ?? "",
                otherUserId: user.id
            )
        } catch {
            print("Error loading buddy status: \(error)")
            buddyStatus = .notBuddies
        }
        isLoadingBuddyStatus = false
    }
    
    // MARK: - Buddy Action Section
    
    @ViewBuilder
    private func buddyActionSection() -> some View {
        if isLoadingBuddyStatus {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
        } else {
            VStack(spacing: 12) {
                switch buddyStatus {
                case .notBuddies:
                    Button(action: {
                        Task {
                            await sendBuddyRequest()
                        }
                    }) {
                        HStack {
                            if isSendingRequest {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "person.badge.plus")
                                Text("Send Buddy Request")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                    }
                    .disabled(isSendingRequest)
                    
                case .requestSent:
                    HStack {
                        Image(systemName: "clock.fill")
                        Text("Buddy Request Sent")
                    }
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(12)
                    
                case .requestReceived:
                    VStack(spacing: 8) {
                        Text("\(user.username ?? "This user") wants to be your buddy!")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                Task {
                                    await acceptReceivedRequest()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "checkmark")
                                    Text("Accept")
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
                                    await rejectReceivedRequest()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "xmark")
                                    Text("Decline")
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
                    .cornerRadius(12)
                    
                case .buddies:
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.subheadline)
                        Text("you're buddies!")
                            .font(.subheadline)
                    }
                    .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }
    
    private func sendBuddyRequest() async {
        guard let currentUser = authManager.currentUser else { return }
        isSendingRequest = true
        
        do {
            try await firebaseService.sendBuddyRequest(from: currentUser, to: user)
            buddyStatus = .requestSent
        } catch {
            print("Error sending buddy request: \(error)")
        }
        
        isSendingRequest = false
    }
    
    private func acceptReceivedRequest() async {
        guard let currentUserId = authManager.currentUser?.id else { return }
        
        let requestId = BuddyRequest.makeId(fromUserId: user.id, toUserId: currentUserId)
        
        do {
            let doc = try await Firestore.firestore().collection("buddyRequests").document(requestId).getDocument()
            if let request = try? doc.data(as: BuddyRequest.self) {
                try await firebaseService.acceptBuddyRequest(request)
                buddyStatus = .buddies
                // Reload buddies
                await viewModel.loadBuddies(userId: user.id)
            }
        } catch {
            print("Error accepting request: \(error)")
        }
    }
    
    private func rejectReceivedRequest() async {
        guard let currentUserId = authManager.currentUser?.id else { return }
        
        let requestId = BuddyRequest.makeId(fromUserId: user.id, toUserId: currentUserId)
        
        do {
            let doc = try await Firestore.firestore().collection("buddyRequests").document(requestId).getDocument()
            if let request = try? doc.data(as: BuddyRequest.self) {
                try await firebaseService.rejectBuddyRequest(request)
                buddyStatus = .notBuddies
            }
        } catch {
            print("Error rejecting request: \(error)")
        }
    }
    
    // MARK: - Buddies Section
    
    @ViewBuilder
    private func buddiesSection() -> some View {
        NavigationLink(destination: BuddiesListView(buddies: viewModel.buddies, title: "\(user.username ?? "User")'s buddies")) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Text("buddies")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(viewModel.buddies.count)")
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
    private func userProfileHeader() -> some View {
        VStack(spacing: 16) {
            // Profile Image
            GeometryReader { geometry in
                if let imageURLString = user.imageURL,
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
            if let username = user.username {
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
            
            // Rating Stats
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(viewModel.ratings.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Ratings")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                if let avgRating = viewModel.averageRating {
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
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func topItemsSection(title: String, items: [TopItem], type: TopItemType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    topItemRow(item: item, rank: index + 1, type: type)
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
    
    @ViewBuilder
    private func ratingsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("recent reviews")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if viewModel.ratings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("no ratings yet")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.ratings.prefix(10)) { rating in
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

// MARK: - View Model

@MainActor
class OtherUserProfileViewModel: ObservableObject {
    @Published var topArtists: [TopItem] = []
    @Published var topTracks: [TopItem] = []
    @Published var topAlbums: [TopItem] = []
    @Published var ratings: [UserRating] = []
    @Published var buddies: [Buddy] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var averageRating: Double?
    
    private var firebaseService: FirebaseService!
    
    nonisolated init() {}
    
    func initialize(firebaseService: FirebaseService) {
        self.firebaseService = firebaseService
    }
    
    func loadUserData(userId: String) {
        isLoading = true
        
        print("DEBUG: Loading data for userId: \(userId)")
        
        Task {
            do {
                // Load top items, ratings, and buddies in parallel
                async let topItemsTask = firebaseService.getUserTopItems(userId: userId)
                async let ratingsTask = firebaseService.getUserRatings(userId: userId)
                async let buddiesTask = firebaseService.getBuddies(forUserId: userId)
                
                let (topItems, userRatings, userBuddies) = try await (topItemsTask, ratingsTask, buddiesTask)
                
                print("DEBUG: Top items found: \(topItems != nil)")
                print("DEBUG: Ratings count: \(userRatings.count)")
                print("DEBUG: Buddies count: \(userBuddies.count)")
                
                if let topItems = topItems {
                    topArtists = topItems.topArtists
                    topTracks = topItems.topTracks
                    topAlbums = topItems.topAlbums
                    print("DEBUG: Top artists: \(topItems.topArtists.count), tracks: \(topItems.topTracks.count), albums: \(topItems.topAlbums.count)")
                }
                
                ratings = userRatings
                buddies = userBuddies
                
                // Calculate average rating
                if !userRatings.isEmpty {
                    let total = userRatings.reduce(0) { $0 + $1.percentage }
                    averageRating = Double(total) / Double(userRatings.count)
                }
                
                isLoading = false
            } catch {
                print("Error loading user data: \(error)")
                errorMessage = "Failed to load user profile"
                isLoading = false
            }
        }
    }
    
    func loadBuddies(userId: String) async {
        do {
            buddies = try await firebaseService.getBuddies(forUserId: userId)
        } catch {
            print("Error loading buddies: \(error)")
        }
    }
}

#Preview {
    let user = AppUser(
        id: "test",
        firebaseUID: "test",
        username: "testuser",
        usernameLowercase: "testuser"
    )
    
    return NavigationView {
        OtherUserProfileView(user: user)
            .environmentObject(FirebaseService())
            .environmentObject(AuthenticationManager())
    }
}
