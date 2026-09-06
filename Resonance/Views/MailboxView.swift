//
//  MailboxView.swift
//  Resonance
//
//  Created by Claude on 2/11/26.
//

import SwiftUI

struct MailboxView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var buddyManager: BuddyManager
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var ratingsManager: RatingsManager
    @EnvironmentObject var mailboxManager: MailboxManager

    @State private var selectedRatingItem: RatableItem?

    private var isEmpty: Bool {
        buddyManager.pendingRequests.isEmpty &&
        mailboxManager.pendingRecommendations.isEmpty &&
        mailboxManager.notifications.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isEmpty {
                        emptyState
                    } else {
                        if !buddyManager.pendingRequests.isEmpty {
                            buddyRequestsSection
                        }

                        if !mailboxManager.pendingRecommendations.isEmpty {
                            recommendationsSection
                        }

                        if !mailboxManager.notifications.isEmpty {
                            activitySection
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Color(red: 0.15, green: 0.08, blue: 0.18).ignoresSafeArea())
            .refreshable {
                await buddyManager.refresh()
                await mailboxManager.refresh()
            }
            .navigationTitle("mailbox")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selectedRatingItem) { item in
            RatingSheet(item: item, ratingsManager: ratingsManager)
                .environmentObject(authManager)
                .environmentObject(firebaseService)
        }
        .onAppear {
            mailboxManager.initialize(firebaseService: firebaseService)
            buddyManager.initialize(firebaseService: firebaseService)
            if let userId = authManager.currentUser?.id, !authManager.isGuestMode {
                mailboxManager.setUserId(userId)
                buddyManager.setUserId(userId)
            }
        }
        .onChange(of: firebaseService.allRatings) { _ in
            // A new rating may match a pending recommendation, refresh to clear it
            Task { await mailboxManager.refresh() }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.fill")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            Text("Your mailbox is empty")
                .font(.headline)
                .foregroundColor(.white.opacity(0.6))

            Text("Buddy requests, mentions, likes, replies, and music recommendations will show up here")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Buddy Requests Section

    private var buddyRequestsSection: some View {
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
            .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach(buddyManager.pendingRequests) { request in
                    buddyRequestRow(request: request)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func buddyRequestRow(request: BuddyRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
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

            HStack(spacing: 12) {
                Button(action: {
                    Task { await buddyManager.acceptRequest(request) }
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
                    Task { await buddyManager.rejectRequest(request) }
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

    // MARK: - Recommendations Section

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("music recommendations")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                Text("\(mailboxManager.pendingRecommendations.count)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.6, green: 0.4, blue: 0.8))
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            VStack(spacing: 12) {
                ForEach(mailboxManager.pendingRecommendations) { recommendation in
                    recommendationRow(recommendation)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func recommendationRow(_ recommendation: MusicRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                NavigationLink(destination: recommendationDestination(recommendation)) {
                    HStack(alignment: .top, spacing: 12) {
                        if let imageURLString = recommendation.imageURL, let imageURL = URL(string: imageURLString) {
                            AsyncImage(url: imageURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle().fill(Color.white.opacity(0.1))
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(recommendation.itemType == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                        } else {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "music.note")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(recommendationText(recommendation))
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)

                            if let message = recommendation.message, !message.isEmpty {
                                Text("\"\(message)\"")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(2)
                            }

                            Text(recommendation.sentAt, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: { openInSpotify(recommendation) }) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Button(action: {
                    selectedRatingItem = convertToRatableItem(recommendation)
                }) {
                    Text("Review")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.6, green: 0.4, blue: 0.8))
                        .cornerRadius(8)
                }

                Button(action: {
                    Task { await mailboxManager.ignoreRecommendation(recommendation) }
                }) {
                    Text("Ignore")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func recommendationDestination(_ recommendation: MusicRecommendation) -> some View {
        switch recommendation.itemType {
        case .artist:
            ArtistDetailView(
                artistId: recommendation.spotifyId,
                artistName: recommendation.itemName,
                artistImageURL: recommendation.imageURL.flatMap { URL(string: $0) }
            )
        case .album:
            AlbumDetailView(
                albumId: recommendation.spotifyId,
                albumName: recommendation.itemName,
                artistName: recommendation.artistName ?? "",
                imageURL: recommendation.imageURL.flatMap { URL(string: $0) }
            )
        case .track:
            SongDetailView(
                trackId: recommendation.spotifyId,
                trackName: recommendation.itemName,
                artistName: recommendation.artistName ?? "",
                albumName: nil,
                albumId: nil,
                imageURL: recommendation.imageURL.flatMap { URL(string: $0) }
            )
        }
    }

    private func convertToRatableItem(_ recommendation: MusicRecommendation) -> RatableItem? {
        let images: [SpotifyImage]? = recommendation.imageURL.map { urlString in
            [SpotifyImage(url: urlString, height: nil, width: nil)]
        }

        switch recommendation.itemType {
        case .artist:
            let artist = SpotifyArtist(
                id: recommendation.spotifyId,
                name: recommendation.itemName,
                images: images,
                genres: nil,
                popularity: nil
            )
            return .artist(artist)

        case .album:
            let artists = recommendation.artistName.map { name in
                [SpotifyArtistSimple(id: "", name: name)]
            } ?? []
            let album = SpotifyAlbum(
                id: recommendation.spotifyId,
                name: recommendation.itemName,
                artists: artists,
                images: images,
                releaseDate: nil,
                totalTracks: nil
            )
            return .album(album)

        case .track:
            let artists = recommendation.artistName.map { name in
                [SpotifyArtistSimple(id: "", name: name)]
            } ?? []
            let albumSimple = recommendation.imageURL.map { urlString in
                SpotifyAlbumSimple(
                    id: "",
                    name: "",
                    images: [SpotifyImage(url: urlString, height: nil, width: nil)]
                )
            }
            let track = SpotifyTrack(
                id: recommendation.spotifyId,
                name: recommendation.itemName,
                artists: artists,
                album: albumSimple,
                durationMs: nil,
                popularity: nil
            )
            return .track(track)
        }
    }

    private func recommendationText(_ recommendation: MusicRecommendation) -> String {
        let sender = recommendation.senderUsername.map { "@\($0)" } ?? "Someone"
        let typeLabel: String
        switch recommendation.itemType {
        case .artist: typeLabel = "artist"
        case .album: typeLabel = "album"
        case .track: typeLabel = "song"
        }

        if recommendation.itemType != .artist, let artistName = recommendation.artistName {
            return "\(sender) sent you the \(typeLabel) \"\(recommendation.itemName)\" by \(artistName)"
        }
        return "\(sender) sent you the \(typeLabel) \"\(recommendation.itemName)\""
    }

    private func openInSpotify(_ recommendation: MusicRecommendation) {
        let typeString: String
        switch recommendation.itemType {
        case .artist: typeString = "artist"
        case .album: typeString = "album"
        case .track: typeString = "track"
        }

        if let uri = SpotifyService.spotifyURI(type: typeString, id: recommendation.spotifyId),
           UIApplication.shared.canOpenURL(uri) {
            UIApplication.shared.open(uri)
        } else if let webURL = SpotifyService.spotifyWebURL(type: typeString, id: recommendation.spotifyId) {
            UIApplication.shared.open(webURL)
        }
    }

    // MARK: - Activity Section (mentions, likes, replies)

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("activity")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(mailboxManager.notifications) { notification in
                    activityRow(notification)
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .onTapGesture { handleActivityTap(notification) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await mailboxManager.deleteNotification(notification) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }

                    if notification.id != mailboxManager.notifications.last?.id {
                        Divider().background(Color.white.opacity(0.1))
                    }
                }
            }
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func activityRow(_ notification: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !notification.read {
                Circle()
                    .fill(Color(red: 0.6, green: 0.4, blue: 0.8))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 8, height: 8)
            }

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: activityIcon(notification))
                    .font(.subheadline)
                    .foregroundColor(activityIconColor(notification))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(activityText(notification))
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(notification.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer(minLength: 0)
        }
        .opacity(notification.read ? 0.6 : 1.0)
    }

    private func activityIcon(_ notification: AppNotification) -> String {
        switch notification.type {
        case .mention: return "at"
        case .reply: return "arrowshape.turn.up.left.fill"
        case .like: return "heart.fill"
        case .comment: return "bubble.right.fill"
        }
    }

    private func activityIconColor(_ notification: AppNotification) -> Color {
        switch notification.type {
        case .mention: return .blue
        case .reply: return Color(red: 0.6, green: 0.4, blue: 0.8)
        case .like: return .red
        case .comment: return Color(red: 0.6, green: 0.4, blue: 0.8)
        }
    }

    private func activityText(_ notification: AppNotification) -> String {
        let actor = notification.actorUsername.map { "@\($0)" } ?? "Someone"

        switch notification.type {
        case .mention:
            let context = notification.commentId != nil ? "comment" : ((notification.hasReviewContent ?? false) ? "review" : "rating")
            if let itemName = notification.itemName {
                return "\(actor) mentioned you in a \(context) on \(itemName)"
            }
            return "\(actor) mentioned you in a \(context)"

        case .reply:
            if let preview = notification.preview, !preview.isEmpty {
                return "\(actor) replied to your comment: \"\(preview)\""
            }
            return "\(actor) replied to your comment"

        case .like:
            if notification.commentId != nil {
                return "\(actor) liked your comment"
            }
            let label = (notification.hasReviewContent ?? false) ? "review" : "rating"
            if let itemName = notification.itemName {
                return "\(actor) liked your \(label) of \(itemName)"
            }
            return "\(actor) liked your \(label)"

        case .comment:
            let label = (notification.hasReviewContent ?? false) ? "review" : "rating"
            if let preview = notification.preview, !preview.isEmpty {
                return "\(actor) commented on your \(label): \"\(preview)\""
            }
            if let itemName = notification.itemName {
                return "\(actor) commented on your \(label) of \(itemName)"
            }
            return "\(actor) commented on your \(label)"
        }
    }

    private func handleActivityTap(_ notification: AppNotification) {
        Task { await mailboxManager.markNotificationRead(notification) }

        var userInfo: [AnyHashable: Any] = ["type": notification.type.rawValue]
        if let v = notification.ratingId { userInfo["ratingId"] = v }
        if let v = notification.commentId { userInfo["commentId"] = v }
        if let v = notification.spotifyId { userInfo["spotifyId"] = v }
        if let v = notification.itemType { userInfo["itemType"] = v }
        if let v = notification.itemName { userInfo["itemName"] = v }
        if let v = notification.artistName { userInfo["artistName"] = v }
        if let v = notification.imageURL { userInfo["imageURL"] = v }
        if let v = notification.hasReviewContent { userInfo["hasReviewContent"] = v ? "true" : "false" }
        if let v = notification.reviewLength { userInfo["reviewLength"] = v }
        userInfo["likerId"] = notification.actorId
        userInfo["commenterId"] = notification.actorId

        notificationManager.handleNotificationTap(userInfo)
    }
}

#Preview {
    MailboxView()
        .environmentObject(AuthenticationManager())
        .environmentObject(FirebaseService())
        .environmentObject(BuddyManager())
        .environmentObject(NotificationManager())
        .environmentObject(RatingsManager(firebaseService: FirebaseService()))
        .environmentObject(MailboxManager())
}
