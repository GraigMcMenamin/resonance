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
    
    // MARK: - In-Memory Cache
    
    private struct CacheEntry<T> {
        let data: T
        let timestamp: Date
    }
    
    private var artistCache: [String: CacheEntry<SpotifyArtist>] = [:]
    private var albumCache: [String: CacheEntry<SpotifyAlbumFull>] = [:]
    private var trackCache: [String: CacheEntry<SpotifyTrack>] = [:]
    private var searchCache: [String: CacheEntry<SpotifySearchResponse>] = [:]
    private var artistTopTracksCache: [String: CacheEntry<[SpotifyTrack]>] = [:]
    private var artistAlbumsCache: [String: CacheEntry<[SpotifyAlbum]>] = [:]
    
    private let cacheTimeout: TimeInterval = 600 // 10 minutes
    
    private func isCacheValid(_ timestamp: Date) -> Bool {
        Date().timeIntervalSince(timestamp) < cacheTimeout
    }
    
    /// Clear all cached data (useful on memory warnings)
    func clearCache() {
        artistCache.removeAll()
        albumCache.removeAll()
        trackCache.removeAll()
        searchCache.removeAll()
        artistTopTracksCache.removeAll()
        artistAlbumsCache.removeAll()
    }
    
    // MARK: - Search Debouncing
    
    private var searchTask: Task<Void, Never>?
    private let searchDebounceInterval: TimeInterval = 0.4 // 400ms debounce
    
    // MARK: - Rate Limit Handling
    
    private var retryAfterDate: Date?
    
    private func isRateLimited() -> Bool {
        if let retryDate = retryAfterDate, Date() < retryDate {
            return true
        }
        retryAfterDate = nil
        return false
    }
    
    // MARK: - Authentication (via Cloud Function)
    
    func authenticate() async {
        do {
            guard let url = URL(string: "\(SpotifyConfig.cloudFunctionBaseURL)/getSpotifyToken") else {
                print("[SpotifyService] Invalid Cloud Function URL")
                throw SpotifyError.authenticationFailed
            }
            
            print("[SpotifyService] Authenticating via \(url)")
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[SpotifyService] No HTTP response")
                throw SpotifyError.authenticationFailed
            }
            
            print("[SpotifyService] Response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                if let responseString = String(data: data, encoding: .utf8) {
                    print("[SpotifyService] Error response: \(responseString)")
                }
                throw SpotifyError.authenticationFailed
            }
            
            struct TokenResponse: Decodable {
                let accessToken: String
                let expiresIn: Int
            }
            
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            self.accessToken = tokenResponse.accessToken
            self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            self.isAuthenticated = true
            self.errorMessage = nil
            print("[SpotifyService] Successfully authenticated")
        } catch {
            print("[SpotifyService] Authentication error: \(error)")
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
    
    // MARK: - Core API Request (with retry-after handling)
    
    private func makeAPIRequest<T: Decodable>(url: URL, type: T.Type) async throws -> T {
        await ensureAuthenticated()
        
        guard let token = accessToken else {
            throw SpotifyError.notAuthenticated
        }
        
        // Check rate limit
        if isRateLimited() {
            throw SpotifyError.rateLimited
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyError.requestFailed
        }
        
        switch httpResponse.statusCode {
        case 200:
            return try JSONDecoder().decode(T.self, from: data)
        case 429:
            // Rate limited - respect Retry-After header
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) } ?? 5.0
            retryAfterDate = Date().addingTimeInterval(retryAfter)
            print("[SpotifyService] Rate limited. Retry after \(retryAfter)s")
            throw SpotifyError.rateLimited
        case 401:
            // Token expired, try once more
            await authenticate()
            guard let newToken = accessToken else {
                throw SpotifyError.notAuthenticated
            }
            var retryRequest = URLRequest(url: url)
            retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
            guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                  retryHttpResponse.statusCode == 200 else {
                throw SpotifyError.requestFailed
            }
            return try JSONDecoder().decode(T.self, from: retryData)
        default:
            throw SpotifyError.requestFailed
        }
    }
    
    // MARK: - Search
    
    func search(query: String, type: SearchType) async throws -> SpotifySearchResponse {
        let cacheKey = "\(query)_\(type.rawValue)"
        
        // Check cache
        if let cached = searchCache[cacheKey], isCacheValid(cached.timestamp) {
            return cached.data
        }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let typeString = type.rawValue
        let urlString = "https://api.spotify.com/v1/search?q=\(encodedQuery)&type=\(typeString)&limit=20"
        
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        let result: SpotifySearchResponse = try await makeAPIRequest(url: url, type: SpotifySearchResponse.self)
        
        // Cache the result
        searchCache[cacheKey] = CacheEntry(data: result, timestamp: Date())
        
        return result
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
        // Check cache
        if let cached = artistCache[id], isCacheValid(cached.timestamp) {
            return cached.data
        }
        
        let urlString = "https://api.spotify.com/v1/artists/\(id)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        let result: SpotifyArtist = try await makeAPIRequest(url: url, type: SpotifyArtist.self)
        artistCache[id] = CacheEntry(data: result, timestamp: Date())
        return result
    }
    
    func getArtistTopTracks(id: String, market: String = "US") async throws -> [SpotifyTrack] {
        // Check cache
        if let cached = artistTopTracksCache[id], isCacheValid(cached.timestamp) {
            return cached.data
        }
        
        let urlString = "https://api.spotify.com/v1/artists/\(id)/top-tracks?market=\(market)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        let topTracksResponse: SpotifyTopTracksResponse = try await makeAPIRequest(url: url, type: SpotifyTopTracksResponse.self)
        artistTopTracksCache[id] = CacheEntry(data: topTracksResponse.tracks, timestamp: Date())
        return topTracksResponse.tracks
    }
    
    func getArtistAlbums(id: String, limit: Int = 10) async throws -> [SpotifyAlbum] {
        // Check cache
        let cacheKey = "\(id)_\(limit)"
        if let cached = artistAlbumsCache[cacheKey], isCacheValid(cached.timestamp) {
            return cached.data
        }
        
        let urlString = "https://api.spotify.com/v1/artists/\(id)/albums?include_groups=album,single&limit=\(limit)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        let albumsResponse: SpotifyAlbumsResponse = try await makeAPIRequest(url: url, type: SpotifyAlbumsResponse.self)
        artistAlbumsCache[cacheKey] = CacheEntry(data: albumsResponse.items, timestamp: Date())
        return albumsResponse.items
    }
    
    // MARK: - Album Details
    
    func getAlbum(id: String) async throws -> SpotifyAlbumFull {
        // Check cache
        if let cached = albumCache[id], isCacheValid(cached.timestamp) {
            return cached.data
        }
        
        let urlString = "https://api.spotify.com/v1/albums/\(id)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        let result: SpotifyAlbumFull = try await makeAPIRequest(url: url, type: SpotifyAlbumFull.self)
        albumCache[id] = CacheEntry(data: result, timestamp: Date())
        return result
    }
    
    // MARK: - Track Details
    
    func getTrack(id: String) async throws -> SpotifyTrack {
        // Check cache
        if let cached = trackCache[id], isCacheValid(cached.timestamp) {
            return cached.data
        }
        
        let urlString = "https://api.spotify.com/v1/tracks/\(id)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        let result: SpotifyTrack = try await makeAPIRequest(url: url, type: SpotifyTrack.self)
        trackCache[id] = CacheEntry(data: result, timestamp: Date())
        return result
    }
    
    // MARK: - Spotify Deep Links (Required by Spotify Policy)
    
    /// Generate a Spotify URI for opening content in the Spotify app
    static func spotifyURI(type: String, id: String) -> URL? {
        URL(string: "spotify:\(type):\(id)")
    }
    
    /// Generate a Spotify web URL for linking back to content (required by policy)
    static func spotifyWebURL(type: String, id: String) -> URL? {
        URL(string: "https://open.spotify.com/\(type)/\(id)")
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
    case rateLimited
    
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
        case .rateLimited:
            return "Too many requests. Please try again shortly."
        }
    }
}
