//
//  BuddyBoardView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import SwiftUI

struct BuddyBoardView: View {
    @EnvironmentObject var ratingsManager: RatingsManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var buddyManager: BuddyManager
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var selectedFilter: RatingFilter = .all
    @State private var selectedSection: LibrarySection = .buddyReviews
    @State private var buddyRatings: [UserRating] = []
    @State private var buddyRecommendations: [MusicRecommendation] = []
    @State private var buddyFeedItems: [BuddyFeedItem] = []
    @State private var isLoadingBuddyRatings = false
    @State private var deepLinkScrollToId: String? = nil
    @State private var pendingScrollId: String? = nil
    @State private var navigateToDeepLinkReviews = false
    @State private var deepLinkReviewsDestination: NotificationDeepLink? = nil
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Hidden NavigationLink for deep link to ReviewsListView
                NavigationLink(
                    destination: deepLinkReviewsView,
                    isActive: $navigateToDeepLinkReviews
                ) {
                    EmptyView()
                }
                .hidden()
                .frame(width: 0, height: 0)
                
                // Section Picker (My Ratings vs Buddy Ratings)
                Picker("Section", selection: $selectedSection) {
                    Text("buddy board").tag(LibrarySection.buddyReviews)
                    Text("my ratings").tag(LibrarySection.myRatings)
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
            .navigationTitle(selectedSection == .myRatings ? "my board" : "buddy board")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedSection) { newValue in
                if newValue == .buddyReviews {
                    Task {
                        await loadBuddyRatings()
                    }
                }
            }
            .onChange(of: buddyManager.buddies) { _ in
                // Reload buddy ratings when buddies list changes
                if selectedSection == .buddyReviews {
                    Task {
                        await loadBuddyRatings()
                    }
                }
            }
            .onAppear {
                if selectedSection == .buddyReviews {
                    Task {
                        await loadBuddyRatings()
                    }
                }
                // Check for deep link that was set before view appeared (cold start)
                if let deepLink = notificationManager.pendingDeepLink {
                    handleDeepLink(deepLink)
                }
            }
            .onChange(of: notificationManager.pendingDeepLink) { deepLink in
                handleDeepLink(deepLink)
            }
        }
    }
    
    // MARK: - Deep Link Handling
    
    @ViewBuilder
    private var deepLinkReviewsView: some View {
        if case .reviewsList(let spotifyId, let itemName, let artistName, let imageURL, let itemType, let scrollToReviewId) = deepLinkReviewsDestination {
            let reviewType: Review.ReviewType = {
                switch itemType {
                case "artist": return .artist
                case "album": return .album
                default: return .track
                }
            }()
            ReviewsListView(
                spotifyId: spotifyId,
                itemName: itemName,
                artistName: artistName,
                imageURL: imageURL.flatMap { URL(string: $0) },
                reviewType: reviewType,
                scrollToReviewId: scrollToReviewId
            )
        } else {
            EmptyView()
        }
    }
    
    private func handleDeepLink(_ deepLink: NotificationDeepLink?) {
        guard let deepLink = deepLink else { return }
        
        // Don't consume deep links meant for other tabs
        switch deepLink {
        case .homePage:
            return
        default:
            break
        }
        
        // Consume the deep link
        notificationManager.pendingDeepLink = nil
        
        switch deepLink {
        case .buddyRatingFeed(let scrollToId):
            selectedSection = .buddyReviews
            if let scrollToId = scrollToId {
                // If feed is already loaded, scroll immediately; otherwise store for later
                if !buddyFeedItems.isEmpty {
                    deepLinkScrollToId = scrollToId
                } else {
                    // Feed not loaded yet - store and it will be applied after load
                    pendingScrollId = scrollToId
                }
            }
        case .reviewsList:
            selectedSection = .buddyReviews
            deepLinkReviewsDestination = deepLink
            // Slight delay to ensure navigation hierarchy is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                navigateToDeepLinkReviews = true
            }
        case .homePage:
            break
        case .profilePage:
            break
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
            
            // Always use a List so pull-to-refresh works in all states
            List {
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredRatings) { rating in
                        NavigationLink(destination: destinationView(for: rating)) {
                            RatingRow(rating: rating)
                        }
                        .onAppear {
                            if rating.id == filteredRatings.last?.id,
                               ratingsManager.hasMoreRatings,
                               let userId = authManager.currentUser?.id {
                                Task { await ratingsManager.loadMoreUserRatings(userId: userId) }
                            }
                        }
                    }
                    .onDelete(perform: deleteRatings)

                    if ratingsManager.isLoading && !ratingsManager.ratings.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                if let userId = authManager.currentUser?.id {
                    await ratingsManager.refreshUserRatings(userId: userId)
                }
            }
        }
    }
    
    // MARK: - Buddy Ratings Section
    
    private var buddyReviewsSection: some View {
        VStack(spacing: 0) {
            if isLoadingBuddyRatings {
                Spacer()
                ProgressView("loading activity...")
                Spacer()
            } else if buddyFeedItems.isEmpty {
                List {
                    VStack(spacing: 12) {
                        Image(systemName: buddyManager.buddies.isEmpty ? "person.2.slash" : "star.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text(buddyManager.buddies.isEmpty ? "no buddies yet" : "no activity yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(buddyManager.buddies.isEmpty ? "add buddies to see their ratings here" : "rate some music to see your activity here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .refreshable {
                    await loadBuddyRatings()
                }
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(buddyFeedItems) { item in
                            switch item {
                            case .rating(let rating):
                                LibraryBuddyRatingRow(rating: rating)
                                    .listRowInsets(EdgeInsets())
                                    .id(item.id)
                            case .recommendation(let rec, let receiverRating):
                                NavigationLink(destination: destinationView(forRecommendation: rec)) {
                                    RecommendationFeedRow(
                                        recommendation: rec,
                                        receiverRating: receiverRating,
                                        currentUserId: authManager.currentUser?.id
                                    )
                                }
                                .id(item.id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await loadBuddyRatings()
                    }
                    .onChange(of: deepLinkScrollToId) { scrollId in
                        if let scrollId = scrollId {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation {
                                    proxy.scrollTo(scrollId, anchor: .top)
                                }
                                deepLinkScrollToId = nil
                            }
                        }
                    }
                }
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
        let currentUserId = authManager.currentUser?.id ?? ""
        
        print("Loading buddy ratings for \(buddyIds.count) buddies: \(buddyIds)")
        
        // Get buddy ratings from allRatings (already loaded via listener)
        // Include both buddy ratings AND current user's own ratings
        let buddyIdSet = Set(buddyIds)
        buddyRatings = ratingsManager.allRatings
            .filter { buddyIdSet.contains($0.userId) || $0.userId == currentUserId }
            .sorted { $0.dateRated > $1.dateRated }
        
        print("Found \(buddyRatings.count) buddy ratings")
        
        // Also load recommendations (only if there are buddies)
        if !buddyIds.isEmpty {
            do {
                buddyRecommendations = try await firebaseService.getBuddyRecommendations(
                    buddyIds: buddyIds,
                    currentUserId: currentUserId
                )
                print("Found \(buddyRecommendations.count) recommendations")
            } catch {
                print("Error loading recommendations: \(error)")
                buddyRecommendations = []
            }
        } else {
            buddyRecommendations = []
        }
        
        // Build combined feed
        buildBuddyFeed()
        
        isLoadingBuddyRatings = false
        
        // Apply any pending scroll from a deep link that arrived before data loaded
        if let scrollId = pendingScrollId {
            pendingScrollId = nil
            deepLinkScrollToId = scrollId
        }
    }
    
    private func buildBuddyFeed() {
        var feedItems: [BuddyFeedItem] = []
        
        // Add ratings as feed items
        for rating in buddyRatings {
            feedItems.append(.rating(rating))
        }
        
        // Add recommendations as feed items
        for rec in buddyRecommendations {
            // Find if receiver has rated this item
            let receiverRating = ratingsManager.allRatings.first {
                $0.userId == rec.receiverId && $0.spotifyId == rec.spotifyId
            }
            feedItems.append(.recommendation(rec, receiverRating: receiverRating))
        }
        
        // Sort by date (most recent first)
        buddyFeedItems = feedItems.sorted { $0.date > $1.date }
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
    
    @ViewBuilder
    private func destinationView(forRecommendation rec: MusicRecommendation) -> some View {
        switch rec.itemType {
        case .artist:
            ArtistDetailView(
                artistId: rec.spotifyId,
                artistName: rec.itemName,
                artistImageURL: rec.imageURL.flatMap { URL(string: $0) }
            )
        case .album:
            AlbumDetailView(
                albumId: rec.spotifyId,
                albumName: rec.itemName,
                artistName: rec.artistName ?? "",
                imageURL: rec.imageURL.flatMap { URL(string: $0) }
            )
        case .track:
            SongDetailView(
                trackId: rec.spotifyId,
                trackName: rec.itemName,
                artistName: rec.artistName ?? "",
                albumName: nil,
                albumId: nil,
                imageURL: rec.imageURL.flatMap { URL(string: $0) }
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
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(rating.dateRated.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
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
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var buddyManager: BuddyManager
    
    @State private var isLiked = false
    @State private var likesCount = 0
    @State private var commentsCount = 0
    @State private var showComments = false
    @State private var comments: [ReviewComment] = []
    @State private var commentLikeCounts: [String: Int] = [:]
    @State private var newCommentText = ""
    @FocusState private var isCommentFieldFocused: Bool
    @State private var isLoadingComments = false
    @State private var isSubmittingComment = false
    @State private var isTogglingLike = false
    @State private var navigateToMusic = false
    @State private var navigateToReviews = false
    @State private var navigateToProfile = false
    @State private var showAllComments = false
    @State private var hasLoadedInteractions = false
    @State private var hasLoadedComments = false
    
    private let maxCommentLength = 100
    private let maxVisibleComments = 3
    
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
    
    private var buddyIds: Set<String> {
        Set(buddyManager.buddies.map { $0.id })
    }
    
    private var reviewType: Review.ReviewType {
        switch rating.type {
        case .artist: return .artist
        case .album: return .album
        case .track: return .track
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Hidden NavigationLink for profile
            NavigationLink(destination: BuddyProfileDestination(userId: rating.userId), isActive: $navigateToProfile) {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)
            
            // Header with buddy info
            HStack(spacing: 8) {
                // Buddy avatar - tappable to view profile
                Button(action: { navigateToProfile = true }) {
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
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                    )
                            }
                        }
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            )
                    }
                }
                .buttonStyle(.plain)
                
                Text(rating.username ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(rating.dateRated.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Item info - tappable to navigate to music page
            NavigationLink(destination: musicDestination, isActive: $navigateToMusic) {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)
            
            // Hidden NavigationLink for reviews
            NavigationLink(destination: reviewsDestination, isActive: $navigateToReviews) {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)
            
            Button(action: { navigateToMusic = true }) {
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
                    
                    Spacer()
                    
                    // Percentage badge
                    Text("\(rating.percentage)%")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(percentageColor)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .buttonStyle(.plain)
            
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
            
            // Like and Comment buttons on bottom right
            HStack {
                Spacer()
                
                HStack(spacing: 16) {
                    // Like button - always likes the rating directly
                    Button(action: toggleLike) {
                        HStack(spacing: 4) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 14))
                                .foregroundColor(isLiked ? .red : .white.opacity(0.6))
                            
                            if likesCount > 0 {
                                Text("\(likesCount)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isTogglingLike || authManager.currentUser == nil)
                    
                    // Comment button
                    Button(action: handleCommentTap) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                            
                            if commentsCount > 0 {
                                Text("\(commentsCount)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
            
            // Inline comments section
            if !comments.isEmpty || (!rating.hasReviewContent && showComments) {
                commentsSection
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .task {
            guard !hasLoadedInteractions else { return }
            hasLoadedInteractions = true
            await loadInteractions()
            // Auto-load comments for inline display
            await loadComments()
        }
        .onAppear {
            if !hasLoadedInteractions {
                likesCount = rating.likesCount ?? 0
                commentsCount = rating.commentsCount ?? 0
            }
        }
    }
    
    // MARK: - Navigation Destinations
    
    @ViewBuilder
    private var musicDestination: some View {
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
    private var reviewsDestination: some View {
        ReviewsListView(
            spotifyId: rating.spotifyId,
            itemName: rating.name,
            artistName: rating.artistName,
            imageURL: rating.imageURL.flatMap { URL(string: $0) },
            reviewType: reviewType,
            scrollToReviewId: rating.id
        )
    }
    
    // MARK: - Comment Tap Handler
    
    private func handleCommentTap() {
        if rating.hasReviewContent {
            // Has a written review: navigate to ReviewsListView and scroll to this review
            navigateToReviews = true
        } else {
            // No written review: toggle the comment input field
            withAnimation {
                showComments.toggle()
            }
        }
    }
    
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showComments && authManager.currentUser != nil {
                HStack(spacing: 8) {
                    TextField("Add a comment...", text: $newCommentText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                        .foregroundColor(.white)
                        .focused($isCommentFieldFocused)
                        .onChange(of: newCommentText) { newValue in
                            if newValue.count > maxCommentLength {
                                newCommentText = String(newValue.prefix(maxCommentLength))
                            }
                        }
                    
                    Button(action: submitComment) {
                        if isSubmittingComment {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(newCommentText.isEmpty ? .white.opacity(0.3) : Color(red: 0.4, green: 0.2, blue: 0.6))
                        }
                    }
                    .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingComment)
                }
                
                if !newCommentText.isEmpty {
                    Text("\(newCommentText.count)/\(maxCommentLength)")
                        .font(.caption2)
                        .foregroundColor(newCommentText.count >= maxCommentLength ? .orange : .white.opacity(0.4))
                }
            }
            
            if !comments.isEmpty {
                let visibleComments = showAllComments ? sortedComments : Array(sortedComments.prefix(maxVisibleComments))
                ForEach(visibleComments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("@\(comment.username ?? "user") commented")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        
                        CommentRow(
                            comment: comment,
                            reviewId: rating.id,
                            initialLikesCount: commentLikeCounts[comment.id] ?? 0,
                            onDelete: {
                                await deleteComment(comment)
                            },
                            largerIcons: true
                        )
                        .environmentObject(authManager)
                        .environmentObject(firebaseService)
                    }
                    .id(comment.id)
                }
                
                if sortedComments.count > maxVisibleComments && !showAllComments {
                    Button(action: { withAnimation { showAllComments = true } }) {
                        Text("show \(sortedComments.count - maxVisibleComments) more comment\(sortedComments.count - maxVisibleComments == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                } else if showAllComments && sortedComments.count > maxVisibleComments {
                    Button(action: { withAnimation { showAllComments = false } }) {
                        Text("show less")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.8))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }
    
    private var sortedComments: [ReviewComment] {
        let buddyComments = comments.filter { buddyIds.contains($0.userId) }
        let otherComments = comments.filter { !buddyIds.contains($0.userId) }
        
        let sortedBuddyComments = buddyComments.sorted {
            (commentLikeCounts[$0.id] ?? 0) > (commentLikeCounts[$1.id] ?? 0)
        }
        let sortedOtherComments = otherComments.sorted {
            (commentLikeCounts[$0.id] ?? 0) > (commentLikeCounts[$1.id] ?? 0)
        }
        
        return sortedBuddyComments + sortedOtherComments
    }
    
    private func loadInteractions() async {
        do {
            likesCount = try await firebaseService.getReviewLikesCount(reviewId: rating.id)
            
            if let userId = authManager.currentUser?.id {
                isLiked = try await firebaseService.hasUserLikedReview(reviewId: rating.id, userId: userId)
            }
            
            commentsCount = try await firebaseService.getReviewCommentsCount(reviewId: rating.id)
        } catch {
            print("Error loading interactions: \(error)")
        }
    }
    
    private func loadComments() async {
        guard !hasLoadedComments else { return }
        hasLoadedComments = true
        isLoadingComments = true
        do {
            comments = try await firebaseService.getReviewComments(reviewId: rating.id)
            
            for comment in comments {
                let count = try await firebaseService.getCommentLikesCount(reviewId: rating.id, commentId: comment.id)
                commentLikeCounts[comment.id] = count
            }
        } catch {
            print("Error loading comments: \(error)")
            hasLoadedComments = false // Allow retry on error
        }
        isLoadingComments = false
    }
    
    private func toggleLike() {
        guard let user = authManager.currentUser else { return }
        
        isTogglingLike = true
        
        Task {
            do {
                if isLiked {
                    try await firebaseService.unlikeReview(reviewId: rating.id, userId: user.id)
                    await MainActor.run {
                        isLiked = false
                        likesCount = max(0, likesCount - 1)
                    }
                } else {
                    try await firebaseService.likeReview(reviewId: rating.id, user: user)
                    await MainActor.run {
                        isLiked = true
                        likesCount += 1
                    }
                }
            } catch {
                print("Error toggling like: \(error)")
            }
            
            await MainActor.run {
                isTogglingLike = false
            }
        }
    }
    
    private func submitComment() {
        guard let user = authManager.currentUser else { return }
        let trimmedComment = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedComment.isEmpty else { return }
        
        let finalComment = String(trimmedComment.prefix(maxCommentLength))
        
        isSubmittingComment = true
        
        Task {
            do {
                let comment = try await firebaseService.addComment(to: rating.id, content: finalComment, user: user)
                await MainActor.run {
                    comments.append(comment)
                    commentLikeCounts[comment.id] = 0
                    commentsCount += 1
                    newCommentText = ""
                    isCommentFieldFocused = false
                    showComments = false
                }
            } catch {
                print("Error submitting comment: \(error)")
            }
            
            await MainActor.run {
                isSubmittingComment = false
            }
        }
    }
    
    private func deleteComment(_ comment: ReviewComment) async {
        do {
            try await firebaseService.deleteComment(reviewId: rating.id, commentId: comment.id)
            await MainActor.run {
                comments.removeAll { $0.id == comment.id }
                commentLikeCounts.removeValue(forKey: comment.id)
                commentsCount = max(0, commentsCount - 1)
            }
        } catch {
            print("Error deleting comment: \(error)")
        }
    }
}

// MARK: - Recommendation Feed Row

/// Shows a music recommendation in the buddy feed
/// Displays "X sent Y <music>" with status and optional rating
struct RecommendationFeedRow: View {
    let recommendation: MusicRecommendation
    let receiverRating: UserRating?
    let currentUserId: String?
    
    private var percentageColor: Color {
        guard let rating = receiverRating else { return .gray }
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
        switch recommendation.itemType {
        case .artist: return "music.mic"
        case .album: return "square.stack"
        case .track: return "music.note"
        }
    }
    
    private var isCurrentUserReceiver: Bool {
        recommendation.receiverId == currentUserId
    }
    
    private var senderName: String {
        recommendation.senderUsername ?? "unknown"
    }
    
    private var receiverName: String {
        recommendation.receiverUsername ?? "unknown"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: "sender sent receiver"
            HStack(spacing: 6) {
                // Sender avatar
                avatarView(imageURL: recommendation.senderImageURL)
                
                Text(senderName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("sent")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Receiver avatar
                avatarView(imageURL: recommendation.receiverImageURL)
                
                Text(receiverName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(recommendation.sentAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Sender's message (if any) - "and said: message"
            if let message = recommendation.message, !message.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text("and said:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                .padding(.leading, 30)
            }
            
            // Music item
            HStack(spacing: 12) {
                // Item image
                if let imageURLString = recommendation.imageURL, let url = URL(string: imageURLString) {
                    CustomAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 50)
                                .clipShape(recommendation.itemType == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                        default:
                            Image(systemName: itemTypeIcon)
                                .font(.title2)
                                .foregroundColor(.gray)
                                .frame(width: 50, height: 50)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(recommendation.itemType == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                        }
                    }
                } else {
                    Image(systemName: itemTypeIcon)
                        .font(.title2)
                        .foregroundColor(.gray)
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(recommendation.itemType == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.itemName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let artistName = recommendation.artistName {
                        Text(artistName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Rating badge or pending status
                if let rating = receiverRating {
                    Text("\(rating.percentage)%")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(percentageColor)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.title3)
                            .foregroundColor(.orange)
                        Text(isCurrentUserReceiver ? "tap to rate" : "pending")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Show receiver's review if they rated it
            if let rating = receiverRating, rating.hasReviewContent, let content = rating.reviewContent {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(receiverName)'s review:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(content)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(3)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func avatarView(imageURL: String?) -> some View {
        if let urlString = imageURL, let url = URL(string: urlString) {
            CustomAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                default:
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        )
                }
            }
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                )
        }
    }
}

#Preview {
    let firebaseService = FirebaseService()
    BuddyBoardView()
        .environmentObject(RatingsManager(firebaseService: firebaseService))
        .environmentObject(firebaseService)
        .environmentObject(AuthenticationManager())
        .environmentObject(BuddyManager())
}
