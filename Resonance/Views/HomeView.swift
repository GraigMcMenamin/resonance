//
//  HomeView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/17/26.
//

import SwiftUI

enum TimePeriod: String, CaseIterable {
    case allTime = "all time"
    case yearly = "this year"
    case monthly = "this month"
    case weekly = "this week"
    
    var dateFilter: Date? {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .allTime:
            return nil
        case .yearly:
            return calendar.date(byAdding: .year, value: -1, to: now)
        case .monthly:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: now)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var firebaseService: FirebaseService
    @State private var selectedPeriod: TimePeriod = .weekly
    @State private var topSongs: [AggregatedRating] = []
    @State private var topArtists: [AggregatedRating] = []
    @State private var topAlbums: [AggregatedRating] = []
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Charts Header with Sort Button
                        HStack {
                            Text("charts")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Menu {
                                ForEach(TimePeriod.allCases, id: \.self) { period in
                                    Button(action: {
                                        selectedPeriod = period
                                    }) {
                                        HStack {
                                            Text(period.rawValue)
                                            if selectedPeriod == period {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(selectedPeriod.rawValue)
                                        .font(.subheadline)
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        // Top Songs Chart
                        ChartSection(
                            title: "top rated songs",
                            items: topSongs,
                            type: .track
                        )
                        
                        // Top Artists Chart
                        ChartSection(
                            title: "top rated artists",
                            items: topArtists,
                            type: .artist
                        )
                        
                        // Top Albums Chart
                        ChartSection(
                            title: "top rated albums",
                            items: topAlbums,
                            type: .album
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("home")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: selectedPeriod) { oldValue, newValue in
            print("📅 [HomeView] Period changed to \(newValue.rawValue)")
            updateCharts()
        }
        .onChange(of: firebaseService.allRatings) { oldValue, newValue in
            print("🔄 [HomeView] Ratings changed: \(oldValue.count) → \(newValue.count)")
            updateCharts()
        }
        .onAppear {
            print("👀 [HomeView] Appeared, updating charts...")
            updateCharts()
        }
    }
    
    private func updateCharts() {
        let filterDate = selectedPeriod.dateFilter
        
        print("📊 [HomeView] Updating charts with \(firebaseService.allRatings.count) total ratings")
        
        // Filter ratings by time period
        let filteredRatings = firebaseService.allRatings.filter { rating in
            guard let filterDate = filterDate else { return true }
            return rating.dateRated >= filterDate
        }
        
        print("🔍 [HomeView] Filtered to \(filteredRatings.count) ratings for period: \(selectedPeriod.rawValue)")
        
        // Get aggregated ratings by type
        topSongs = getAggregatedRatings(from: filteredRatings, type: .track, limit: 10)
        topArtists = getAggregatedRatings(from: filteredRatings, type: .artist, limit: 10)
        topAlbums = getAggregatedRatings(from: filteredRatings, type: .album, limit: 10)
        
        print("🎵 [HomeView] Charts updated: \(topSongs.count) songs, \(topArtists.count) artists, \(topAlbums.count) albums")
    }
    
    private func getAggregatedRatings(from ratings: [UserRating], type: UserRating.RatingType, limit: Int) -> [AggregatedRating] {
        // Filter by type
        let typeRatings = ratings.filter { $0.type == type }
        
        // Group by Spotify ID
        let grouped = Dictionary(grouping: typeRatings) { $0.spotifyId }
        
        // Create aggregated ratings
        let aggregated = grouped.compactMap { spotifyId, userRatings -> AggregatedRating? in
            guard let first = userRatings.first else { return nil }
            
            let total = userRatings.reduce(0) { $0 + $1.percentage }
            let average = Double(total) / Double(userRatings.count)
            
            return AggregatedRating(
                id: spotifyId,
                type: first.type,
                name: first.name,
                artistName: first.artistName,
                imageURL: first.imageURL,
                averagePercentage: average,
                totalRatings: userRatings.count,
                userRatings: userRatings,
                currentUserRating: nil
            )
        }
        
        // Sort by average percentage and limit
        return aggregated
            .sorted { $0.averagePercentage > $1.averagePercentage }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Time Period Picker

struct TimePeriodPicker: View {
    @Binding var selectedPeriod: TimePeriod
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(TimePeriod.allCases, id: \.self) { period in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPeriod = period
                    }
                }) {
                    Text(period.rawValue)
                        .font(.subheadline)
                        .fontWeight(selectedPeriod == period ? .semibold : .regular)
                        .foregroundColor(selectedPeriod == period ? .black : .white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedPeriod == period ? Color.white : Color.white.opacity(0.1))
                        )
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Chart Section

struct ChartSection: View {
    let title: String
    let items: [AggregatedRating]
    let type: UserRating.RatingType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal)
            
            if items.isEmpty {
                EmptyChartView()
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(destination: destinationView(for: item)) {
                            ChartItemRow(
                                rank: index + 1,
                                item: item,
                                type: type
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    @ViewBuilder
    private func destinationView(for item: AggregatedRating) -> some View {
        switch item.type {
        case .artist:
            ArtistDetailView(
                artistId: item.id,
                artistName: item.name,
                artistImageURL: item.imageURL.flatMap { URL(string: $0) }
            )
        case .album:
            AlbumDetailView(
                albumId: item.id,
                albumName: item.name,
                artistName: item.artistName ?? "",
                imageURL: item.imageURL.flatMap { URL(string: $0) }
            )
        case .track:
            SongDetailView(
                trackId: item.id,
                trackName: item.name,
                artistName: item.artistName ?? "",
                albumName: nil,
                albumId: nil,
                imageURL: item.imageURL.flatMap { URL(string: $0) }
            )
        }
    }
}

// MARK: - Chart Item Row

struct ChartItemRow: View {
    let rank: Int
    let item: AggregatedRating
    let type: UserRating.RatingType
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank
            Text("\(rank)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 25)
            
            // Album Art
            AsyncImage(url: item.imageURL.flatMap { URL(string: $0) }) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 45, height: 45)
            .clipShape(type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let artistName = item.artistName {
                    Text(artistName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    Text("\(item.totalRatings) rating\(item.totalRatings == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Percentage
            Text(String(format: "%.1f%%", item.averagePercentage))
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Chevron
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
}

// MARK: - Rating Bar

struct RatingBar: View {
    let percentage: Double
    
    var color: Color {
        switch percentage {
        case 80...100:
            return .green
        case 60..<80:
            return .yellow
        case 40..<60:
            return .orange
        default:
            return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                    
                    // Filled portion
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * (percentage / 100))
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Empty Chart View

struct EmptyChartView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No ratings yet")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
            
            Text("Be the first to rate something!")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    HomeView()
        .environmentObject(FirebaseService())
}
