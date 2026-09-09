//
//  RankingViews.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 9/5/26.
//
//  Views for creating, browsing, and displaying user rankings (named, ordered
//  lists of songs, albums, or artists).
//

import SwiftUI

// MARK: - Ranking Summary Content (shared compact display)

/// The compact "card" content shared by RankingRow (my ratings list) and
/// RankingFeedRow (buddy board): #1 item image, ranking name, and item count.
struct RankingSummaryContent: View {
    let ranking: UserRanking
    var imageSize: CGFloat = 60
    var showDate: Bool = true
    
    private var itemTypeIcon: String {
        switch ranking.type {
        case .artist: return "music.mic"
        case .album: return "square.stack"
        case .track: return "music.note"
        }
    }
    
    private var itemTypeLabel: String {
        switch ranking.type {
        case .artist: return ranking.itemCount == 1 ? "artist" : "artists"
        case .album: return ranking.itemCount == 1 ? "album" : "albums"
        case .track: return ranking.itemCount == 1 ? "song" : "songs"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // #1 ranked item's image
            if let urlString = ranking.topItem?.imageURL, let url = URL(string: urlString) {
                CustomAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: imageSize, height: imageSize)
                            .clipShape(ranking.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                    default:
                        rankingPlaceholder
                    }
                }
            } else {
                rankingPlaceholder
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(ranking.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(ranking.itemCount) \(itemTypeLabel)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if showDate {
                Text((ranking.dateUpdated ?? ranking.dateCreated).formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var rankingPlaceholder: some View {
        Image(systemName: itemTypeIcon)
            .font(.title2)
            .foregroundColor(.gray)
            .frame(width: imageSize, height: imageSize)
            .background(Color.gray.opacity(0.2))
            .clipShape(ranking.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
    }
}

// MARK: - Ranking Row (used in "my ratings" list)

struct RankingRow: View {
    let ranking: UserRanking
    
    var body: some View {
        RankingSummaryContent(ranking: ranking)
            .padding(.vertical, 4)
    }
}

// MARK: - Ranking Feed Row (used in the buddy board feed)

struct RankingFeedRow: View {
    let ranking: UserRanking
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @State private var navigateToProfile = false
    @State private var navigateToDetail = false
    @State private var navigateToCommentUserId: String? = nil
    
    @State private var isLiked = false
    @State private var likesCount = 0
    @State private var commentsCount = 0
    @State private var showComments = false
    @State private var comments: [ReviewComment] = []
    @State private var commentLikeCounts: [String: Int] = [:]
    @State private var newCommentText = ""
    @FocusState private var isCommentFieldFocused: Bool
    @State private var isSubmittingComment = false
    @State private var isTogglingLike = false
    @State private var showAllComments = false
    @State private var hasLoadedInteractions = false
    @State private var hasLoadedComments = false
    @State private var sourceId = UUID()
    
    private let maxVisibleComments = 3
    
    private var displayName: String {
        ranking.username ?? "unknown"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Grouped into a single zero-size container so it only contributes one
            // layout gap, and so List doesn't add its own disclosure chevron.
            ZStack {
                NavigationLink(destination: BuddyProfileDestination(userId: ranking.userId), isActive: $navigateToProfile) { EmptyView() }
                NavigationLink(destination: RankingDetailView(ranking: ranking), isActive: $navigateToDetail) { EmptyView() }
                NavigationLink(
                    destination: BuddyProfileDestination(userId: navigateToCommentUserId ?? ""),
                    isActive: Binding(
                        get: { navigateToCommentUserId != nil },
                        set: { if !$0 { navigateToCommentUserId = nil } }
                    )
                ) { EmptyView() }
            }
            .hidden()
            .frame(width: 0, height: 0)
            
            HStack(spacing: 6) {
                Button(action: { navigateToProfile = true }) {
                    HStack(spacing: 6) {
                        avatarView
                        Text(displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                
                Text("made a ranking")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text((ranking.dateUpdated ?? ranking.dateCreated).formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Button(action: { navigateToDetail = true }) {
                RankingSummaryContent(ranking: ranking, imageSize: 50, showDate: false)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            
            // Like and Comment buttons on bottom right
            HStack {
                Spacer()
                
                HStack(spacing: 16) {
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
            
            if !comments.isEmpty || showComments {
                commentsSection
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .task {
            guard !hasLoadedInteractions else { return }
            hasLoadedInteractions = true
            await loadInteractions()
            await loadComments()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewCommentAdded)) { note in
            guard let payload = note.object as? ReviewCommentAddedPayload,
                  payload.reviewId == ranking.id,
                  payload.sourceId != sourceId else { return }
            if !comments.contains(where: { $0.id == payload.comment.id }) {
                comments.append(payload.comment)
                commentLikeCounts[payload.comment.id] = 0
            }
            commentsCount += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviewCommentDeleted)) { note in
            guard let payload = note.object as? ReviewCommentDeletedPayload,
                  payload.reviewId == ranking.id,
                  payload.sourceId != sourceId else { return }
            comments.removeAll { $0.id == payload.commentId }
            commentLikeCounts.removeValue(forKey: payload.commentId)
            commentsCount = max(0, commentsCount - 1)
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
                            if newValue.count > 150 {
                                newCommentText = String(newValue.prefix(150))
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
            }
            
            if !comments.isEmpty {
                let visibleComments = showAllComments ? sortedComments : Array(sortedComments.prefix(maxVisibleComments))
                ForEach(visibleComments) { comment in
                    CommentRow(
                        comment: comment,
                        reviewId: ranking.id,
                        initialLikesCount: commentLikeCounts[comment.id] ?? 0,
                        onDelete: {
                            await deleteComment(comment)
                        },
                        onReply: { _ in },
                        onUserTap: handleCommentUserTap,
                        largerIcons: true
                    )
                    .environmentObject(authManager)
                    .environmentObject(firebaseService)
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
        comments.sorted { $0.createdAt > $1.createdAt }
    }
    
    private func handleCommentTap() {
        withAnimation {
            showComments.toggle()
        }
        Task { await loadComments() }
    }
    
    private func handleCommentUserTap(_ userId: String) {
        if authManager.currentUser?.id == userId {
            return
        }
        navigateToCommentUserId = userId
    }
    
    private func loadInteractions() async {
        do {
            likesCount = try await firebaseService.getReviewLikesCount(reviewId: ranking.id)
            
            if let userId = authManager.currentUser?.id {
                isLiked = try await firebaseService.hasUserLikedReview(reviewId: ranking.id, userId: userId)
            }
            
            commentsCount = try await firebaseService.getReviewCommentsCount(reviewId: ranking.id)
        } catch {
            print("Error loading interactions: \(error)")
        }
    }
    
    private func loadComments() async {
        guard !hasLoadedComments else { return }
        hasLoadedComments = true
        do {
            comments = try await firebaseService.getReviewComments(reviewId: ranking.id)
            
            for comment in comments {
                let count = try await firebaseService.getCommentLikesCount(reviewId: ranking.id, commentId: comment.id)
                commentLikeCounts[comment.id] = count
            }
        } catch {
            print("Error loading comments: \(error)")
            hasLoadedComments = false // Allow retry on error
        }
    }
    
    private func toggleLike() {
        guard let user = authManager.currentUser else { return }
        
        isTogglingLike = true
        
        Task {
            do {
                if isLiked {
                    try await firebaseService.unlikeReview(reviewId: ranking.id, userId: user.id)
                    await MainActor.run {
                        isLiked = false
                        likesCount = max(0, likesCount - 1)
                    }
                } else {
                    try await firebaseService.likeReview(reviewId: ranking.id, user: user)
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
        
        isCommentFieldFocused = false
        
        let finalComment = String(trimmedComment.prefix(150))
        
        isSubmittingComment = true
        
        Task {
            do {
                let comment = try await firebaseService.addComment(
                    to: ranking.id,
                    content: finalComment,
                    user: user
                )
                await MainActor.run {
                    comments.append(comment)
                    commentLikeCounts[comment.id] = 0
                    commentsCount += 1
                    newCommentText = ""
                    isCommentFieldFocused = false
                    showComments = false
                    NotificationCenter.default.post(
                        name: .reviewCommentAdded,
                        object: ReviewCommentAddedPayload(reviewId: ranking.id, comment: comment, sourceId: sourceId)
                    )
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
            try await firebaseService.deleteComment(reviewId: ranking.id, commentId: comment.id)
            await MainActor.run {
                comments.removeAll { $0.id == comment.id }
                commentLikeCounts.removeValue(forKey: comment.id)
                commentsCount = max(0, commentsCount - 1)
                NotificationCenter.default.post(
                    name: .reviewCommentDeleted,
                    object: ReviewCommentDeletedPayload(reviewId: ranking.id, commentId: comment.id, sourceId: sourceId)
                )
            }
        } catch {
            print("Error deleting comment: \(error)")
        }
    }
    
    @ViewBuilder
    private var avatarView: some View {
        if let urlString = ranking.userImageURL, let url = URL(string: urlString) {
            CustomAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                default:
                    defaultAvatar
                }
            }
        } else {
            defaultAvatar
        }
    }
    
    private var defaultAvatar: some View {
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

// MARK: - Ranking Detail View (full ordered list)

struct RankingDetailView: View {
    let ranking: UserRanking
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var rankingsManager: RankingsManager
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var showingEditRanking = false
    @State private var currentRanking: UserRanking
    
    init(ranking: UserRanking) {
        self.ranking = ranking
        _currentRanking = State(initialValue: ranking)
    }
    
    private var isOwner: Bool {
        authManager.currentUser?.id == currentRanking.userId
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.15, green: 0.08, blue: 0.18)
                .ignoresSafeArea()
            
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentRanking.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        if let username = currentRanking.username {
                            Text("by \(username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let description = currentRanking.description, !description.isEmpty {
                            Text(description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color(red: 0.15, green: 0.08, blue: 0.18))
                }
                
                Section {
                    ForEach(Array(currentRanking.items.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink(destination: destinationView(for: entry)) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, alignment: .leading)
                                
                                if let urlString = entry.imageURL, let url = URL(string: urlString) {
                                    CustomAsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 50, height: 50)
                                                .clipShape(currentRanking.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                                        default:
                                            itemPlaceholder
                                        }
                                    }
                                } else {
                                    itemPlaceholder
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    if let artistName = entry.artistName {
                                        Text(artistName)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
        }
        .navigationTitle("ranking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingEditRanking = true }) {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .alert("Delete Ranking", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await rankingsManager.deleteRanking(id: currentRanking.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this ranking?")
        }
        .fullScreenCover(isPresented: $showingEditRanking, onDismiss: {
            if let updated = rankingsManager.getRanking(id: currentRanking.id) {
                currentRanking = updated
            }
        }) {
            CreateRankingView(rankingsManager: rankingsManager, existingRanking: currentRanking)
        }
    }
    
    private var itemPlaceholder: some View {
        Image(systemName: currentRanking.type == .artist ? "music.mic" : (currentRanking.type == .album ? "square.stack" : "music.note"))
            .font(.title3)
            .foregroundColor(.gray)
            .frame(width: 50, height: 50)
            .background(Color.gray.opacity(0.2))
            .clipShape(currentRanking.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
    }
    
    @ViewBuilder
    private func destinationView(for entry: RankingEntry) -> some View {
        switch currentRanking.type {
        case .artist:
            ArtistDetailView(
                artistId: entry.spotifyId,
                artistName: entry.name,
                artistImageURL: entry.imageURL.flatMap { URL(string: $0) }
            )
        case .album:
            AlbumDetailView(
                albumId: entry.spotifyId,
                albumName: entry.name,
                artistName: entry.artistName ?? "",
                imageURL: entry.imageURL.flatMap { URL(string: $0) }
            )
        case .track:
            SongDetailView(
                trackId: entry.spotifyId,
                trackName: entry.name,
                artistName: entry.artistName ?? "",
                albumName: nil,
                albumId: nil,
                imageURL: entry.imageURL.flatMap { URL(string: $0) }
            )
        }
    }
}

// MARK: - Create Ranking View

struct CreateRankingView: View {
    @ObservedObject var rankingsManager: RankingsManager
    var existingRanking: UserRanking? = nil
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var spotifyService: SpotifyService
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var description: String
    @State private var type: UserRanking.RankingType
    @State private var items: [RankingEntry]
    @State private var showItemSearch = false
    @State private var showAlbumSearchForTracks = false
    @State private var showArtistSearchForAlbums = false
    @State private var isSaving = false
    @State private var isPopulating = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case name, description
    }
    
    private let descriptionLimit = 150
    
    // Explicit row color so it matches the previous sheet's "elevated" look, since fullScreenCover doesn't apply that automatically.
    private let rowBackgroundColor = Color(red: 0.24, green: 0.15, blue: 0.28)
    
    init(rankingsManager: RankingsManager, existingRanking: UserRanking? = nil) {
        self.rankingsManager = rankingsManager
        self.existingRanking = existingRanking
        _name = State(initialValue: existingRanking?.name ?? "")
        _description = State(initialValue: existingRanking?.description ?? "")
        _type = State(initialValue: existingRanking?.type ?? .track)
        _items = State(initialValue: existingRanking?.items ?? [])
    }
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !items.isEmpty
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Form {
                        Section("ranking name") {
                            TextField("e.g. Top 5 Sad Songs", text: $name)
                                .focused($focusedField, equals: .name)
                        }
                        .listRowBackground(rowBackgroundColor)
                        
                        Section("description") {
                            TextField("add a description (optional)", text: $description, axis: .vertical)
                                .lineLimit(3, reservesSpace: false)
                                .focused($focusedField, equals: .description)
                                .onChange(of: description) { newValue in
                                    if newValue.count > descriptionLimit {
                                        description = String(newValue.prefix(descriptionLimit))
                                    }
                                }
                            Text("\(description.count)/\(descriptionLimit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .listRowBackground(rowBackgroundColor)
                        
                        Section("type") {
                            Picker("Type", selection: $type) {
                                Text("songs").tag(UserRanking.RankingType.track)
                                Text("artists").tag(UserRanking.RankingType.artist)
                                Text("albums").tag(UserRanking.RankingType.album)
                            }
                            .pickerStyle(.segmented)
                            .disabled(!items.isEmpty)
                        }
                        .listRowBackground(rowBackgroundColor)
                        
                        Section("autofill (optional)") {
                            Button(action: { showAlbumSearchForTracks = true }) {
                                Label("all songs on an album", systemImage: "square.stack")
                            }
                            .disabled(!items.isEmpty || isPopulating)
                            
                            Button(action: { showArtistSearchForAlbums = true }) {
                                Label("all albums by an artist", systemImage: "music.mic")
                            }
                            .disabled(!items.isEmpty || isPopulating)
                            
                            if isPopulating {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                            }
                        }
                        .listRowBackground(rowBackgroundColor)
                        
                        Section("items (drag to reorder)") {
                            ForEach(items) { entry in
                                HStack(spacing: 12) {
                                    Text("\(items.firstIndex(where: { $0.id == entry.id }).map { $0 + 1 } ?? 0)")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, alignment: .leading)
                                    Text(entry.name)
                                        .lineLimit(1)
                                }
                            }
                            .onMove { indices, newOffset in
                                focusedField = nil
                                items.move(fromOffsets: indices, toOffset: newOffset)
                            }
                            .onDelete { offsets in
                                items.remove(atOffsets: offsets)
                            }
                            
                            Button(action: { showItemSearch = true }) {
                                Label("add item", systemImage: "plus.circle.fill")
                            }
                        }
                        .listRowBackground(rowBackgroundColor)
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .listRowBackground(rowBackgroundColor)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.immediately)
                    .environment(\.editMode, .constant(.active))
                }
            }
            .tint(.white)
            .navigationTitle(existingRanking == nil ? "new ranking" : "edit ranking")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $showItemSearch) {
                RankingItemSearchSheet(type: type) { entry in
                    if !items.contains(where: { $0.spotifyId == entry.spotifyId }) {
                        items.append(entry)
                    }
                }
                .environmentObject(spotifyService)
            }
            .sheet(isPresented: $showAlbumSearchForTracks) {
                RankingItemSearchSheet(type: .album) { entry in
                    Task { await populateAlbumTracks(albumId: entry.spotifyId, albumName: entry.name) }
                }
                .environmentObject(spotifyService)
            }
            .sheet(isPresented: $showArtistSearchForAlbums) {
                RankingItemSearchSheet(type: .artist) { entry in
                    Task { await populateArtistAlbums(artistId: entry.spotifyId, artistName: entry.name) }
                }
                .environmentObject(spotifyService)
            }
        }
    }
    
    private func populateAlbumTracks(albumId: String, albumName: String) async {
        isPopulating = true
        errorMessage = nil
        do {
            let album = try await spotifyService.getAlbum(id: albumId)
            let albumImageURL = album.imageURL?.absoluteString
            type = .track
            items = album.tracks.items.map { track in
                RankingEntry(spotifyId: track.id, name: track.name, artistName: track.artistNames, imageURL: albumImageURL)
            }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = albumName
            }
        } catch {
            errorMessage = "Failed to load album tracks: \(error.localizedDescription)"
        }
        isPopulating = false
    }
    
    private func populateArtistAlbums(artistId: String, artistName: String) async {
        isPopulating = true
        errorMessage = nil
        do {
            let albums = try await spotifyService.getArtistAlbums(id: artistId, limit: 50)
            let fullLengthAlbums = albums.filter { ($0.totalTracks ?? 0) >= 5 }
            type = .album
            items = fullLengthAlbums.map { album in
                RankingEntry(spotifyId: album.id, name: album.name, artistName: album.artistNames, imageURL: album.imageURL?.absoluteString)
            }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = "\(artistName) albums"
            }
        } catch {
            errorMessage = "Failed to load artist albums: \(error.localizedDescription)"
        }
        isPopulating = false
    }
    
    private func save() async {
        guard let user = authManager.currentUser else { return }
        isSaving = true
        errorMessage = nil
        
        let ranking = UserRanking(
            id: existingRanking?.id ?? UUID().uuidString,
            userId: user.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(descriptionLimit)),
            type: type,
            items: items,
            dateCreated: existingRanking?.dateCreated ?? Date(),
            dateUpdated: existingRanking == nil ? nil : Date(),
            username: user.username,
            userImageURL: user.displayImageURL
        )
        
        await rankingsManager.addOrUpdateRanking(ranking)
        isSaving = false
        dismiss()
    }
}

// MARK: - Ranking Item Search Sheet

/// Search restricted to a single item type, used when adding items to a ranking.
struct RankingItemSearchSheet: View {
    let type: UserRanking.RankingType
    let onSelect: (RankingEntry) -> Void
    
    @EnvironmentObject var spotifyService: SpotifyService
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var artists: [SpotifyArtist] = []
    @State private var albums: [SpotifyAlbum] = []
    @State private var tracks: [SpotifyTrack] = []
    @State private var isLoading = false
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18)
                    .ignoresSafeArea()
                
                List {
                    switch type {
                    case .artist:
                        ForEach(artists) { artist in
                            Button {
                                onSelect(RankingEntry(spotifyId: artist.id, name: artist.name, artistName: nil, imageURL: artist.imageURL?.absoluteString))
                                dismiss()
                            } label: {
                                resultRow(name: artist.name, subtitle: nil, imageURL: artist.imageURL)
                            }
                        }
                    case .album:
                        ForEach(albums) { album in
                            Button {
                                onSelect(RankingEntry(spotifyId: album.id, name: album.name, artistName: album.artistNames, imageURL: album.imageURL?.absoluteString))
                                dismiss()
                            } label: {
                                resultRow(name: album.name, subtitle: album.artistNames, imageURL: album.imageURL)
                            }
                        }
                    case .track:
                        ForEach(tracks) { track in
                            Button {
                                onSelect(RankingEntry(spotifyId: track.id, name: track.name, artistName: track.artistNames, imageURL: track.imageURL?.absoluteString))
                                dismiss()
                            } label: {
                                resultRow(name: track.name, subtitle: track.artistNames, imageURL: track.imageURL)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "search")
            .onChange(of: searchText) { newValue in
                performSearch(newValue)
            }
            .navigationTitle("add item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    @ViewBuilder
    private func resultRow(name: String, subtitle: String?, imageURL: URL?) -> some View {
        HStack(spacing: 12) {
            CustomAsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                default:
                    Image(systemName: type == .artist ? "music.mic" : (type == .album ? "square.stack" : "music.note"))
                        .foregroundColor(.gray)
                        .frame(width: 50, height: 50)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    private func performSearch(_ query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            artists = []
            albums = []
            tracks = []
            return
        }
        searchTask = Task {
            isLoading = true
            do {
                switch type {
                case .artist:
                    let result = try await spotifyService.searchArtists(query: query)
                    if !Task.isCancelled { artists = result }
                case .album:
                    let result = try await spotifyService.searchAlbums(query: query)
                    if !Task.isCancelled { albums = result }
                case .track:
                    let result = try await spotifyService.searchTracks(query: query)
                    if !Task.isCancelled { tracks = result }
                }
            } catch {
                print("Error searching: \(error)")
            }
            isLoading = false
        }
    }
}
