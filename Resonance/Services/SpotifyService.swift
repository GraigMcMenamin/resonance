//
//  SpotifyService.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import Foundation
import Combine

@MainActor
class SpotifyService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    private var accessToken: String?
    private var tokenExpirationDate: Date?
    
    // MARK: - Authentication
    
    func authenticate() async {
        do {
            let authString = "\(SpotifyConfig.clientId):\(SpotifyConfig.clientSecret)"
            guard let authData = authString.data(using: .utf8) else {
                throw SpotifyError.authenticationFailed
            }
            let base64Auth = authData.base64EncodedString()
            
            var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
            request.httpMethod = "POST"
            request.setValue("Basic \(base64Auth)", forHTTPHeaderField: "Authorization")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "grant_type=client_credentials".data(using: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw SpotifyError.authenticationFailed
            }
            
            let authResponse = try JSONDecoder().decode(SpotifyAuthResponse.self, from: data)
            self.accessToken = authResponse.accessToken
            self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(authResponse.expiresIn))
            self.isAuthenticated = true
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Authentication failed: \(error.localizedDescription)"
            self.isAuthenticated = false
        }
    }
    
    private func ensureAuthenticated() async {
        if let expirationDate = tokenExpirationDate, Date() < expirationDate {
            return
        }
        await authenticate()
    }
    
    // MARK: - Search
    
    func search(query: String, type: SearchType) async throws -> SpotifySearchResponse {
        await ensureAuthenticated()
        
        guard let token = accessToken else {
            throw SpotifyError.notAuthenticated
        }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let typeString = type.rawValue
        let urlString = "https://api.spotify.com/v1/search?q=\(encodedQuery)&type=\(typeString)&limit=20"
        
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.requestFailed
        }
        
        return try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
    }
    
    func searchArtists(query: String) async throws -> [SpotifyArtist] {
        let response = try await search(query: query, type: .artist)
        return response.artists?.items ?? []
    }
    
    func searchAlbums(query: String) async throws -> [SpotifyAlbum] {
        let response = try await search(query: query, type: .album)
        return response.albums?.items ?? []
    }
    
    func searchTracks(query: String) async throws -> [SpotifyTrack] {
        let response = try await search(query: query, type: .track)
        return response.tracks?.items ?? []
    }
    
    enum SearchType: String {
        case artist
        case album
        case track
    }
    
    // MARK: - Artist Details
    
    func getArtist(id: String) async throws -> SpotifyArtist {
        await ensureAuthenticated()
        
        guard let token = accessToken else {
            throw SpotifyError.notAuthenticated
        }
        
        let urlString = "https://api.spotify.com/v1/artists/\(id)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.requestFailed
        }
        
        return try JSONDecoder().decode(SpotifyArtist.self, from: data)
    }
    
    func getArtistTopTracks(id: String, market: String = "US") async throws -> [SpotifyTrack] {
        await ensureAuthenticated()
        
        guard let token = accessToken else {
            throw SpotifyError.notAuthenticated
        }
        
        let urlString = "https://api.spotify.com/v1/artists/\(id)/top-tracks?market=\(market)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.requestFailed
        }
        
        let topTracksResponse = try JSONDecoder().decode(SpotifyTopTracksResponse.self, from: data)
        return topTracksResponse.tracks
    }
    
    func getArtistAlbums(id: String, limit: Int = 10) async throws -> [SpotifyAlbum] {
        await ensureAuthenticated()
        
        guard let token = accessToken else {
            throw SpotifyError.notAuthenticated
        }
        
        let urlString = "https://api.spotify.com/v1/artists/\(id)/albums?include_groups=album,single&limit=\(limit)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.requestFailed
        }
        
        let albumsResponse = try JSONDecoder().decode(SpotifyAlbumsResponse.self, from: data)
        return albumsResponse.items
    }
    
    // MARK: - Album Details
    
    func getAlbum(id: String) async throws -> SpotifyAlbumFull {
        await ensureAuthenticated()
        
        guard let token = accessToken else {
            throw SpotifyError.notAuthenticated
        }
        
        let urlString = "https://api.spotify.com/v1/albums/\(id)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.requestFailed
        }
        
        return try JSONDecoder().decode(SpotifyAlbumFull.self, from: data)
    }
    
    // MARK: - Track Details
    
    func getTrack(id: String) async throws -> SpotifyTrack {
        await ensureAuthenticated()
        
        guard let token = accessToken else {
            throw SpotifyError.notAuthenticated
        }
        
        let urlString = "https://api.spotify.com/v1/tracks/\(id)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.requestFailed
        }
        
        return try JSONDecoder().decode(SpotifyTrack.self, from: data)
    }
}

// MARK: - Additional Response Models

struct SpotifyTopTracksResponse: Codable {
    let tracks: [SpotifyTrack]
}

// MARK: - Errors

enum SpotifyError: LocalizedError {
    case notAuthenticated
    case authenticationFailed
    case invalidURL
    case requestFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Spotify"
        case .authenticationFailed:
            return "Failed to authenticate with Spotify"
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed:
            return "Request failed"
        }
    }
}
