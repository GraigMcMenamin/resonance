//
//  LibraryView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var ratingsManager: RatingsManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var buddyManager: BuddyManager
    @State private var selectedFilter: RatingFilter = .all
    @State private var selectedSection: LibrarySection = .myRatings
    @State private var buddyRatings: [UserRating] = []
    @State private var isLoadingBuddyRatings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Section Picker (My Ratings vs Buddy Ratings)
                Picker("Section", selection: $selectedSection) {
                    Text("my ratings").tag(LibrarySection.myRatings)
                    Text("buddy ratings").tag(LibrarySection.buddyReviews)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)
                
                if selectedSection == .myRatings {
                    myRatingsSection
                } else {
                    buddyReviewsSection
                }
            }
            .navigationTitle(selectedSection == .myRatings ? "me" : "my buddies")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedSection) { oldValue, newValue in
                if newValue == .buddyReviews {
                    Task {
                        await loadBuddyRatings()
                    }
                }
            }
            .onChange(of: buddyManager.buddies) { oldValue, newValue in
                // Reload buddy ratings when buddies list changes
                if selectedSection == .buddyReviews {
                    Task {
                        await loadBuddyRatings()
                    }
                }
            }
        }
    }
    
    // MARK: - My Ratings Section
    
    private var myRatingsSection: some View {
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
            
            // Stats Card
            if !filteredRatings.isEmpty {
                StatsCard(ratings: filteredRatings, filter: selectedFilter)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            
            // Ratings List
            if filteredRatings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("no ratings yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("search and rate your favorite music")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredRatings) { rating in
                        NavigationLink(destination: destinationView(for: rating)) {
                            RatingRow(rating: rating)
                        }
                    }
                    .onDelete(perform: deleteRatings)
                }
                .listStyle(.plain)
            }
        }
    }
    
    // MARK: - Buddy Ratings Section
    
    private var buddyReviewsSection: some View {
        VStack(spacing: 0) {
            if isLoadingBuddyRatings {
                Spacer()
                ProgressView("loading buddy ratings...")
                Spacer()
            } else if buddyManager.buddies.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("no buddies yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("add buddies to see their ratings here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else if buddyRatings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("no buddy ratings yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("your buddies haven't rated anything")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                // Stats for buddy ratings
                BuddyRatingsStatsCard(ratings: buddyRatings)
                    .padding(.horizontal)
                    .padding(.vertical)
                
                List {
                    ForEach(buddyRatings) { rating in
                        NavigationLink(destination: destinationView(for: rating)) {
                            LibraryBuddyRatingRow(rating: rating)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func loadBuddyRatings() async {
        isLoadingBuddyRatings = true
        
        // Ensure buddies are loaded first
        if buddyManager.buddies.isEmpty, let userId = authManager.currentUser?.id {
            print("Buddies not loaded yet, loading...")
            buddyManager.initialize(firebaseService: firebaseService)
            await buddyManager.loadAllBuddyData(userId: userId)
        }
        
        let buddyIds = buddyManager.buddies.map { $0.id }
        
        print("Loading buddy ratings for \(buddyIds.count) buddies: \(buddyIds)")
        
        guard !buddyIds.isEmpty else {
            print("No buddies found, skipping rating fetch")
            isLoadingBuddyRatings = false
            return
        }
        
        // Get buddy ratings from allRatings (already loaded via listener)
        let buddyIdSet = Set(buddyIds)
        buddyRatings = ratingsManager.allRatings
            .filter { buddyIdSet.contains($0.userId) }
            .sorted { $0.dateRated > $1.dateRated }
        
        print("Found \(buddyRatings.count) buddy ratings")
        
        isLoadingBuddyRatings = false
    }
    
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
    
    private var filteredRatings: [UserRating] {
        switch selectedFilter {
        case .all:
            return ratingsManager.allRatingsSorted
        case .artists:
            return ratingsManager.getRatings(ofType: .artist)
        case .albums:
            return ratingsManager.getRatings(ofType: .album)
        case .songs:
            return ratingsManager.getRatings(ofType: .track)
        }
    }
    
    private func deleteRatings(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let rating = filteredRatings[index]
                await ratingsManager.deleteRating(id: rating.id)
            }
        }
    }
}

// MARK: - Stats Card

struct StatsCard: View {
    let ratings: [UserRating]
    let filter: RatingFilter
    
    private var averagePercentage: Int {
        let sum = ratings.reduce(0) { $0 + $1.percentage }
        return sum / ratings.count
    }
    
    private var percentageColor: Color {
        let avg = Double(averagePercentage)
        switch avg {
        case 0..<40: return .red
        case 40..<60: return .orange
        case 60..<75: return .yellow
        case 75..<90: return Color(red: 0.6, green: 0.8, blue: 0.2) // yellow-green
        default: return .green
        }
    }
    
    var body: some View {
        HStack(spacing: 24) {
            VStack {
                Text("\(ratings.count)")
                    .font(.system(size: 32, weight: .bold))
                Text(filter == .all ? "total ratings" : "ratings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 50)
            
            VStack {
                Text("\(averagePercentage)%")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(percentageColor)
                Text("average")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Rating Row

struct RatingRow: View {
    let rating: UserRating
    
    private var percentageColor: Color {
        let pct = Double(rating.percentage)
        switch pct {
        case 0..<40: return .red
        case 40..<60: return .orange
        case 60..<75: return .yellow
        case 75..<90: return Color(red: 0.6, green: 0.8, blue: 0.2) // yellow-green
        default: return .green
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Image
                if let urlString = rating.imageURL, let url = URL(string: urlString) {
                    CustomAsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(width: 60, height: 60)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(rating.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
                        case .failure:
                            Image(systemName: rating.type == .artist ? "music.mic" : (rating.type == .album ? "square.stack" : "music.note"))
                                .font(.title)
                                .foregroundColor(.gray)
                                .frame(width: 60, height: 60)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(rating.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
                        @unknown default:
                            Color.gray
                                .frame(width: 60, height: 60)
                                .clipShape(rating.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
                        }
                    }
                } else {
                    Image(systemName: rating.type == .artist ? "music.mic" : (rating.type == .album ? "square.stack" : "music.note"))
                        .font(.title)
                        .foregroundColor(.gray)
                        .frame(width: 60, height: 60)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(rating.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(rating.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let artistName = rating.artistName {
                        Text(artistName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Text(rating.dateRated.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Percentage
                    Text("\(rating.percentage)%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Rating bar
                    RatingBar(percentage: Double(rating.percentage))
                        .frame(width: 80, height: 8)
                }
            }
            
            // Review section
            if rating.hasReviewContent, let content = rating.reviewContent {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "quote.bubble.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("my review")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(content)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.leading, 72) // Align with text content (60px image + 12px spacing)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Filter Enum

enum RatingFilter {
    case all
    case artists
    case albums
    case songs
}

// MARK: - Library Section Enum

enum LibrarySection {
    case myRatings
    case buddyReviews
}

// MARK: - Buddy Ratings Stats Card

struct BuddyRatingsStatsCard: View {
    let ratings: [UserRating]
    
    private var averagePercentage: Int {
        guard !ratings.isEmpty else { return 0 }
        let sum = ratings.reduce(0) { $0 + $1.percentage }
        return sum / ratings.count
    }
    
    private var uniqueBuddyCount: Int {
        Set(ratings.map { $0.userId }).count
    }
    
    private var percentageColor: Color {
        let avg = Double(averagePercentage)
        switch avg {
        case 0..<40: return .red
        case 40..<60: return .orange
        case 60..<75: return .yellow
        case 75..<90: return Color(red: 0.6, green: 0.8, blue: 0.2)
        default: return .green
        }
    }
    
    var body: some View {
        HStack(spacing: 24) {
            VStack {
                Text("\(ratings.count)")
                    .font(.system(size: 32, weight: .bold))
                Text("ratings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 50)
            
            VStack {
                Text("\(uniqueBuddyCount)")
                    .font(.system(size: 32, weight: .bold))
                Text("buddies")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 50)
            
            VStack {
                Text("\(averagePercentage)%")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(percentageColor)
                Text("average")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Buddy Rating Row

struct LibraryBuddyRatingRow: View {
    let rating: UserRating
    
    private var percentageColor: Color {
        let pct = Double(rating.percentage)
        switch pct {
        case 0..<40: return .red
        case 40..<60: return .orange
        case 60..<75: return .yellow
        case 75..<90: return Color(red: 0.6, green: 0.8, blue: 0.2)
        default: return .green
        }
    }
    
    private var itemTypeIcon: String {
        switch rating.type {
        case .artist: return "music.mic"
        case .album: return "square.stack"
        case .track: return "music.note"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with buddy info
            HStack(spacing: 8) {
                // Buddy avatar
                if let imageURLString = rating.userImageURL, let url = URL(string: imageURLString) {
                    CustomAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        default:
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.gray)
                        }
                    }
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(rating.username ?? rating.userName ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(rating.dateRated.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Percentage badge
                Text("\(rating.percentage)%")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(percentageColor)
            }
            
            // Item info
            HStack(spacing: 12) {
                // Item image
                if let imageURLString = rating.imageURL, let url = URL(string: imageURLString) {
                    CustomAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(rating.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                        default:
                            Image(systemName: itemTypeIcon)
                                .font(.title2)
                                .foregroundColor(.gray)
                                .frame(width: 50, height: 50)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(rating.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                        }
                    }
                } else {
                    Image(systemName: itemTypeIcon)
                        .font(.title2)
                        .foregroundColor(.gray)
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(rating.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(rating.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let artistName = rating.artistName {
                        Text(artistName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            // Review content (if they wrote one)
            if rating.hasReviewContent, let content = rating.reviewContent {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(content)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    let firebaseService = FirebaseService()
    LibraryView()
        .environmentObject(RatingsManager(firebaseService: firebaseService))
        .environmentObject(firebaseService)
        .environmentObject(AuthenticationManager())
        .environmentObject(BuddyManager())
}
