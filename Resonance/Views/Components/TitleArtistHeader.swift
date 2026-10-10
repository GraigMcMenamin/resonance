//
//  TitleArtistHeader.swift
//  Resonance
//

import SwiftUI

/// Left-aligned title with the artist link(s) underneath.
struct TitleArtistHeader: View {
    let title: String
    let artists: [SpotifyArtistSimple]
    @ObservedObject var ratingsManager: RatingsManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            
            ForEach(artists, id: \.id) { artistLink($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func artistLink(_ artist: SpotifyArtistSimple) -> some View {
        NavigationLink(destination: ArtistDetailView(
            artistId: artist.id,
            artistName: artist.name,
            artistImageURL: nil
        )) {
            HStack(spacing: 6) {
                Text(artist.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
                
                if let average = ratingsManager.getAverageRating(for: artist.id) {
                    Text("\(Int(average))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
