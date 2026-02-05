//
//  Models.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import Foundation

// MARK: - Spotify Models

struct SpotifyArtist: Codable, Identifiable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    let genres: [String]?
    let popularity: Int?
    
    var imageURL: URL? {
        guard let urlString = images?.first?.url else { return nil }
        return URL(string: urlString)
    }
}

struct SpotifyAlbum: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [SpotifyArtistSimple]
    let images: [SpotifyImage]?
    let releaseDate: String?
    let totalTracks: Int?
    
    var imageURL: URL? {
        guard let urlString = images?.first?.url else { return nil }
        return URL(string: urlString)
    }
    
    var artistNames: String {
        artists.map { $0.name }.joined(separator: ", ")
    }
    
    var releaseYear: String? {
        guard let date = releaseDate else { return nil }
        return String(date.prefix(4))
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, artists, images
        case releaseDate = "release_date"
        case totalTracks = "total_tracks"
    }
}

struct SpotifyTrack: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [SpotifyArtistSimple]
    let album: SpotifyAlbumSimple?
    let durationMs: Int?
    let popularity: Int?
    
    var imageURL: URL? {
        guard let urlString = album?.images?.first?.url else { return nil }
        return URL(string: urlString)
    }
    
    var artistNames: String {
        artists.map { $0.name }.joined(separator: ", ")
    }
    
    var duration: String {
        guard let ms = durationMs else { return "" }
        let seconds = ms / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, artists, album, popularity
        case durationMs = "duration_ms"
    }
}

struct SpotifyArtistSimple: Codable {
    let id: String
    let name: String
}

struct SpotifyAlbumSimple: Codable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    
    var imageURL: URL? {
        guard let urlString = images?.first?.url else { return nil }
        return URL(string: urlString)
    }
}

// Full album with tracks
struct SpotifyAlbumFull: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [SpotifyArtistSimple]
    let images: [SpotifyImage]?
    let releaseDate: String?
    let totalTracks: Int?
    let tracks: SpotifyAlbumTracksResponse
    let label: String?
    let copyrights: [SpotifyCopyright]?
    
    var imageURL: URL? {
        guard let urlString = images?.first?.url else { return nil }
        return URL(string: urlString)
    }
    
    var artistNames: String {
        artists.map { $0.name }.joined(separator: ", ")
    }
    
    var releaseYear: String? {
        guard let date = releaseDate else { return nil }
        return String(date.prefix(4))
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, artists, images, tracks, label, copyrights
        case releaseDate = "release_date"
        case totalTracks = "total_tracks"
    }
}

struct SpotifyAlbumTracksResponse: Codable {
    let items: [SpotifyTrackSimple]
}

struct SpotifyTrackSimple: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [SpotifyArtistSimple]
    let durationMs: Int?
    let trackNumber: Int?
    
    var artistNames: String {
        artists.map { $0.name }.joined(separator: ", ")
    }
    
    var duration: String {
        guard let ms = durationMs else { return "" }
        let seconds = ms / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, artists
        case durationMs = "duration_ms"
        case trackNumber = "track_number"
    }
}

struct SpotifyCopyright: Codable {
    let text: String
    let type: String
}

struct SpotifyImage: Codable {
    let url: String
    let height: Int?
    let width: Int?
}

// MARK: - Search Response Models

struct SpotifySearchResponse: Codable {
    let artists: SpotifyArtistsResponse?
    let albums: SpotifyAlbumsResponse?
    let tracks: SpotifyTracksResponse?
}

struct SpotifyArtistsResponse: Codable {
    let items: [SpotifyArtist]
}

struct SpotifyAlbumsResponse: Codable {
    let items: [SpotifyAlbum]
}

struct SpotifyTracksResponse: Codable {
    let items: [SpotifyTrack]
}

// MARK: - User Models

struct AppUser: Codable, Identifiable {
    let id: String // Firebase UID (for Spotify users: their Spotify ID, for email users: Firebase generated)
    var firebaseUID: String
    var username: String? // Unique Resonance username (case-preserved, but uniqueness is case-insensitive)
    var usernameLowercase: String? // Lowercase version for case-insensitive lookups
    
    // Spotify-specific fields (nil for email/password users)
    var spotifyId: String?
    var spotifyAccessToken: String?
    var spotifyRefreshToken: String?
    var tokenExpirationDate: Date?
    
    // Common fields
    var displayName: String
    var email: String?
    var imageURL: String?
    var createdAt: Date = Date()
    
    // Auth method tracking
    var authMethod: AuthMethod = .spotify
    
    // Push notification tokens (FCM)
    var fcmTokens: [String]?
    
    enum AuthMethod: String, Codable {
        case spotify
        case emailPassword
    }
    
    enum CodingKeys: String, CodingKey {
        case id, firebaseUID, username, usernameLowercase
        case spotifyId, spotifyAccessToken, spotifyRefreshToken, tokenExpirationDate
        case displayName, email, imageURL, createdAt, authMethod, fcmTokens
    }
}

struct SpotifyUserProfile: Codable {
    let id: String
    let displayName: String
    let email: String?
    let images: [SpotifyImage]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case images
    }
}

struct SpotifyTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

// MARK: - User Rating Models

struct UserRating: Codable, Identifiable, Equatable {
    var id: String // Format: "userId_spotifyId" for unique compound key
    let spotifyId: String // Spotify item ID (artist/album/track)
    let userId: String // User who created the rating
    let type: RatingType
    let name: String
    let artistName: String? // For albums and tracks
    let imageURL: String?
    let percentage: Int // 0-100
    let dateRated: Date
    var userName: String? // Display name of the user who rated
    var username: String? // Unique Resonance username
    var userImageURL: String? // Profile image URL of the user who rated
    
    // Review content (optional - can rate without reviewing)
    var reviewContent: String?
    var reviewDateCreated: Date?
    var reviewDateUpdated: Date?
    
    enum RatingType: String, Codable {
        case artist
        case album
        case track
    }
    
    // Helper to create rating ID
    static func makeId(userId: String, spotifyId: String) -> String {
        return "\(userId)_\(spotifyId)"
    }
    
    // Check if this rating has review content
    var hasReviewContent: Bool {
        guard let content = reviewContent else { return false }
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Determine review length based on content
    var reviewLength: Review.ReviewLength? {
        guard let content = reviewContent, hasReviewContent else { return nil }
        return Review.ReviewLength.determine(from: content)
    }
    
    // Convert to Review for backwards compatibility with ReviewCard
    func toReview() -> Review {
        let reviewType: Review.ReviewType
        switch type {
        case .artist: reviewType = .artist
        case .album: reviewType = .album
        case .track: reviewType = .track
        }
        
        return Review(
            id: id,
            spotifyId: spotifyId,
            userId: userId,
            type: reviewType,
            itemName: name,
            artistName: artistName,
            imageURL: imageURL,
            content: reviewContent,
            percentage: percentage,
            reviewLength: reviewLength,
            dateCreated: reviewDateCreated ?? dateRated,
            dateUpdated: reviewDateUpdated,
            userName: userName,
            username: username,
            userImageURL: userImageURL
        )
    }
    
    // Equatable conformance
    static func == (lhs: UserRating, rhs: UserRating) -> Bool {
        lhs.id == rhs.id &&
        lhs.percentage == rhs.percentage &&
        lhs.dateRated == rhs.dateRated &&
        lhs.reviewContent == rhs.reviewContent
    }
}

// MARK: - Aggregated Rating (for displaying averages)

struct AggregatedRating: Identifiable {
    let id: String // Spotify item ID
    let type: UserRating.RatingType
    let name: String
    let artistName: String?
    let imageURL: String?
    let averagePercentage: Double
    let totalRatings: Int
    let userRatings: [UserRating] // All individual ratings
    let currentUserRating: UserRating? // Current user's rating, if any
}

// MARK: - Review Models

struct Review: Codable, Identifiable, Equatable {
    var id: String // Format: "userId_spotifyId" for unique compound key
    let spotifyId: String // Spotify item ID (artist/album/track)
    let userId: String // User who created the review
    let type: ReviewType
    let itemName: String // Name of the song/album/artist
    let artistName: String? // For albums and tracks
    let imageURL: String?
    let content: String? // The review text (optional - can have rating without review)
    let percentage: Int // 0-100 rating percentage (required)
    let reviewLength: ReviewLength? // Short or Long (nil if no review content)
    let dateCreated: Date
    var dateUpdated: Date?
    var userName: String? // Display name of the user who reviewed
    var username: String? // Unique Resonance username
    var userImageURL: String? // Profile image URL of the user who reviewed
    
    // Computed property to check if this has a text review
    var hasReviewContent: Bool {
        guard let content = content else { return false }
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    enum ReviewType: String, Codable {
        case artist
        case album
        case track
    }
    
    enum ReviewLength: String, Codable {
        case short
        case long
        
        static func determine(from content: String) -> ReviewLength {
            return content.count < 150 ? .short : .long
        }
    }
    
    // Helper to create review ID
    static func makeId(userId: String, spotifyId: String) -> String {
        return "\(userId)_\(spotifyId)"
    }
    
    // Equatable conformance
    static func == (lhs: Review, rhs: Review) -> Bool {
        lhs.id == rhs.id &&
        lhs.content == rhs.content &&
        lhs.dateCreated == rhs.dateCreated
    }
}

// MARK: - Review Like Model

struct ReviewLike: Codable, Identifiable, Equatable {
    var id: String // Format: "reviewId_userId"
    let reviewId: String // The review being liked
    let userId: String // User who liked the review
    let username: String? // Username of the liker
    let userDisplayName: String? // Display name of the liker
    let userImageURL: String? // Profile image of the liker
    let createdAt: Date
    
    static func makeId(reviewId: String, userId: String) -> String {
        return "\(reviewId)_\(userId)"
    }
    
    static func == (lhs: ReviewLike, rhs: ReviewLike) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Review Comment Model

struct ReviewComment: Codable, Identifiable, Equatable {
    var id: String // Auto-generated UUID
    let reviewId: String // The review being commented on
    let userId: String // User who wrote the comment
    let username: String? // Username of the commenter
    let userDisplayName: String? // Display name of the commenter
    let userImageURL: String? // Profile image of the commenter
    let content: String // The comment text (max 100 characters)
    let createdAt: Date
    var updatedAt: Date?
    
    static func == (lhs: ReviewComment, rhs: ReviewComment) -> Bool {
        lhs.id == rhs.id &&
        lhs.content == rhs.content
    }
}

// MARK: - Comment Like Model

struct CommentLike: Codable, Identifiable, Equatable {
    var id: String // Format: "commentId_userId"
    let reviewId: String // The review the comment belongs to
    let commentId: String // The comment being liked
    let userId: String // User who liked the comment
    let username: String? // Username of the liker
    let userDisplayName: String? // Display name of the liker
    let createdAt: Date
    
    static func makeId(commentId: String, userId: String) -> String {
        return "\(commentId)_\(userId)"
    }
    
    static func == (lhs: CommentLike, rhs: CommentLike) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Auth Response

struct SpotifyAuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

// MARK: - Custom URLSession for Image Loading

class ImageURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Only bypass certificate validation for Spotify CDN
        if challenge.protectionSpace.host.contains("scdn.co") || challenge.protectionSpace.host.contains("spotifycdn.com") {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

class CustomImageLoader {
    static let shared = CustomImageLoader()
    
    let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        let delegate = ImageURLSessionDelegate()
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}

// MARK: - User Top Items Model

struct UserTopItems: Codable, Identifiable {
    var id: String // userId
    let userId: String
    var topArtists: [TopItem]
    var topTracks: [TopItem]
    var topAlbums: [TopItem]
    var updatedAt: Date = Date()
}

// MARK: - Buddy Request Model

struct BuddyRequest: Codable, Identifiable {
    var id: String // Format: "fromUserId_toUserId"
    let fromUserId: String
    let toUserId: String
    let fromUsername: String
    let fromDisplayName: String
    let fromImageURL: String?
    let toUsername: String?
    let toDisplayName: String
    let toImageURL: String?
    let status: BuddyRequestStatus
    let createdAt: Date
    
    enum BuddyRequestStatus: String, Codable {
        case pending
        case accepted
        case rejected
    }
    
    static func makeId(fromUserId: String, toUserId: String) -> String {
        return "\(fromUserId)_\(toUserId)"
    }
}

// MARK: - Buddy Model (for accepted buddies)

struct Buddy: Codable, Identifiable, Equatable {
    var id: String // The buddy's userId
    let oderId: String
    let username: String?
    let displayName: String
    let imageURL: String?
    let buddySince: Date
}

// MARK: - Top Item Model

struct TopItem: Codable, Identifiable {
    let id: String
    let name: String
    let subtitle: String?
    let imageURL: URL?
    
    init(id: String, name: String, subtitle: String?, imageURL: URL?) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.imageURL = imageURL
    }
    
    init(from artist: SpotifyArtist) {
        self.id = artist.id
        self.name = artist.name
        self.subtitle = artist.genres?.first
        self.imageURL = artist.imageURL
    }
    
    init(from track: SpotifyTrack) {
        self.id = track.id
        self.name = track.name
        self.subtitle = track.artistNames
        self.imageURL = track.imageURL
    }
    
    init(from album: SpotifyAlbum) {
        self.id = album.id
        self.name = album.name
        self.subtitle = album.artistNames
        self.imageURL = album.imageURL
    }
}

// MARK: - Music Recommendation Model

/// Represents a music recommendation sent from one user to another
/// Shows up in the buddy feed for all mutual buddies
struct MusicRecommendation: Codable, Identifiable, Equatable {
    var id: String // Format: "senderId_receiverId_spotifyId_timestamp"
    let senderId: String
    let receiverId: String
    let senderUsername: String?
    let senderDisplayName: String
    let senderImageURL: String?
    let receiverUsername: String?
    let receiverDisplayName: String
    let receiverImageURL: String?
    
    // Music item details
    let spotifyId: String
    let itemType: ItemType
    let itemName: String
    let artistName: String?
    let imageURL: String?
    
    // Optional message from sender (max 100 chars)
    let message: String?
    
    // Timestamps
    let sentAt: Date
    
    // Status tracking
    var status: RecommendationStatus
    var receiverRatingId: String? // Links to the receiver's rating if they rated it
    
    enum ItemType: String, Codable {
        case artist
        case album
        case track
    }
    
    enum RecommendationStatus: String, Codable {
        case pending // Receiver hasn't rated yet
        case rated // Receiver has rated the item
    }
    
    static func makeId(senderId: String, receiverId: String, spotifyId: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(senderId)_\(receiverId)_\(spotifyId)_\(timestamp)"
    }
    
    static func == (lhs: MusicRecommendation, rhs: MusicRecommendation) -> Bool {
        lhs.id == rhs.id &&
        lhs.status == rhs.status &&
        lhs.receiverRatingId == rhs.receiverRatingId
    }
}

/// A combined feed item that can be either a rating or a recommendation
/// Used to display a unified buddy activity feed
enum BuddyFeedItem: Identifiable {
    case rating(UserRating)
    case recommendation(MusicRecommendation, receiverRating: UserRating?)
    
    var id: String {
        switch self {
        case .rating(let rating):
            return "rating_\(rating.id)"
        case .recommendation(let rec, _):
            return "rec_\(rec.id)"
        }
    }
    
    var date: Date {
        switch self {
        case .rating(let rating):
            return rating.dateRated
        case .recommendation(let rec, _):
            return rec.sentAt
        }
    }
}
