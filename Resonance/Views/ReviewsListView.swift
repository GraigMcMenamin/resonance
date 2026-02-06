//
//  ReviewsListView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/24/26.
//

import SwiftUI

struct ReviewsListView: View {
    let spotifyId: String
    let itemName: String
    let artistName: String?
    let imageURL: URL?
    let reviewType: Review.ReviewType
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var buddyManager: BuddyManager
    
    @State private var reviews: [Review] = []
    @State private var reviewLikeCounts: [String: Int] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedLength: Review.ReviewLength = .short
    
    var body: some View {
        ZStack {
            Color(red: 0.15, green: 0.08, blue: 0.18)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                lengthFilterSection
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Spacer()
                } else if let error = errorMessage {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadReviews() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    Spacer()
                } else if sortedFilteredReviews.isEmpty {
                    Spacer()
                    emptyStateView
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(sortedFilteredReviews) { review in
                                ReviewCard(
                                    review: review,
                                    initialLikesCount: reviewLikeCounts[review.id] ?? 0,
                                    buddyIds: buddyIds
                                )
                                .environmentObject(authManager)
                                .environmentObject(firebaseService)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadReviews()
        }
    }
    
    private var lengthFilterSection: some View {
        VStack(spacing: 0) {
            Picker("Review Length", selection: $selectedLength) {
                Text("Short").tag(Review.ReviewLength.short)
                Text("Long").tag(Review.ReviewLength.long)
            }
            .pickerStyle(.segmented)
            .padding()
            
            Divider()
                .background(Color.white.opacity(0.1))
        }
        .background(Color(red: 0.12, green: 0.06, blue: 0.15))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No \(selectedLength == .short ? "short" : "long") reviews yet")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            
            Text("Go back to rate & review this item!")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding()
    }
    
    private var buddyIds: Set<String> {
        Set(buddyManager.buddies.map { $0.id })
    }
    
    private var sortedFilteredReviews: [Review] {
        let filtered = reviews.filter { $0.hasReviewContent && $0.reviewLength == selectedLength }
        let buddyReviews = filtered.filter { buddyIds.contains($0.userId) }
        let otherReviews = filtered.filter { !buddyIds.contains($0.userId) }
        
        let sortedBuddyReviews = buddyReviews.sorted {
            (reviewLikeCounts[$0.id] ?? 0) > (reviewLikeCounts[$1.id] ?? 0)
        }
        let sortedOtherReviews = otherReviews.sorted {
            (reviewLikeCounts[$0.id] ?? 0) > (reviewLikeCounts[$1.id] ?? 0)
        }
        
        return sortedBuddyReviews + sortedOtherReviews
    }
    
    private func loadReviews() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Fetch reviews from ratings collection (new consolidated model)
            reviews = try await firebaseService.fetchReviewsFromRatings(spotifyId: spotifyId)
            
            for review in reviews {
                let count = try await firebaseService.getReviewLikesCount(reviewId: review.id)
                reviewLikeCounts[review.id] = count
            }
        } catch {
            errorMessage = "Failed to load reviews: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

struct ReviewCard: View {
    let review: Review
    let initialLikesCount: Int
    let buddyIds: Set<String>
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    
    @State private var isLiked = false
    @State private var likesCount = 0
    @State private var commentsCount = 0
    @State private var showComments = false
    @State private var comments: [ReviewComment] = []
    @State private var commentLikeCounts: [String: Int] = [:]
    @State private var newCommentText = ""
    @State private var isLoadingComments = false
    @State private var isSubmittingComment = false
    @State private var isTogglingLike = false
    
    private let maxCommentLength = 100
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let imageURLString = review.userImageURL, let imageURL = URL(string: imageURLString) {
                    CustomAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        default:
                            defaultAvatar
                        }
                    }
                } else {
                    defaultAvatar
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    if let username = review.username {
                        Text("@\(username)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    } else {
                        Text("User")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                ratingBadge
            }
            
            if let content = review.content, !content.isEmpty {
                Text(content)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(nil)
            }
            
            if review.dateUpdated != nil {
                Text("edited")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            HStack(spacing: 24) {
                Button(action: toggleLike) {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundColor(isLiked ? .red : .white.opacity(0.6))
                        
                        if likesCount > 0 {
                            Text("\(likesCount)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .disabled(isTogglingLike || authManager.currentUser == nil)
                
                Button(action: {
                    withAnimation {
                        showComments.toggle()
                        if showComments && comments.isEmpty {
                            Task { await loadComments() }
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.6))
                        
                        if commentsCount > 0 {
                            Text("\(commentsCount)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.top, 4)
            
            if showComments {
                commentsSection
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
        .task {
            await loadInteractions()
        }
        .onAppear {
            likesCount = initialLikesCount
        }
    }
    
    private var defaultAvatar: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(.gray)
            )
    }
    
    private var ratingBadge: some View {
        HStack(spacing: 8) {
            Text("\(review.percentage)%")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            RatingBar(percentage: Double(review.percentage))
                .frame(width: 50, height: 6)
        }
    }
    
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            if authManager.currentUser != nil {
                HStack(spacing: 8) {
                    TextField("Add a comment...", text: $newCommentText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(10)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(20)
                        .foregroundColor(.white)
                        .onChange(of: newCommentText) { oldValue, newValue in
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
                                .foregroundColor(newCommentText.isEmpty ? .white.opacity(0.3) : .purple)
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
            
            if isLoadingComments {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if comments.isEmpty {
                Text("No comments yet")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.vertical, 8)
            } else {
                ForEach(sortedComments) { comment in
                    CommentRow(
                        comment: comment,
                        reviewId: review.id,
                        initialLikesCount: commentLikeCounts[comment.id] ?? 0,
                        onDelete: {
                            await deleteComment(comment)
                        }
                    )
                    .environmentObject(authManager)
                    .environmentObject(firebaseService)
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
    
    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: review.dateCreated, relativeTo: Date())
    }
    
    private func loadInteractions() async {
        do {
            likesCount = try await firebaseService.getReviewLikesCount(reviewId: review.id)
            
            if let userId = authManager.currentUser?.id {
                isLiked = try await firebaseService.hasUserLikedReview(reviewId: review.id, userId: userId)
            }
            
            commentsCount = try await firebaseService.getReviewCommentsCount(reviewId: review.id)
        } catch {
            print("Error loading interactions: \(error)")
        }
    }
    
    private func loadComments() async {
        isLoadingComments = true
        do {
            comments = try await firebaseService.getReviewComments(reviewId: review.id)
            
            for comment in comments {
                let count = try await firebaseService.getCommentLikesCount(reviewId: review.id, commentId: comment.id)
                commentLikeCounts[comment.id] = count
            }
        } catch {
            print("Error loading comments: \(error)")
        }
        isLoadingComments = false
    }
    
    private func toggleLike() {
        guard let user = authManager.currentUser else { return }
        
        isTogglingLike = true
        
        Task {
            do {
                if isLiked {
                    try await firebaseService.unlikeReview(reviewId: review.id, userId: user.id)
                    await MainActor.run {
                        isLiked = false
                        likesCount = max(0, likesCount - 1)
                    }
                } else {
                    try await firebaseService.likeReview(reviewId: review.id, user: user)
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
                let comment = try await firebaseService.addComment(to: review.id, content: finalComment, user: user)
                await MainActor.run {
                    comments.append(comment)
                    commentLikeCounts[comment.id] = 0
                    commentsCount += 1
                    newCommentText = ""
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
            try await firebaseService.deleteComment(reviewId: review.id, commentId: comment.id)
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

struct CommentRow: View {
    let comment: ReviewComment
    let reviewId: String
    let initialLikesCount: Int
    let onDelete: () async -> Void
    
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    
    @State private var showDeleteConfirmation = false
    @State private var isLiked = false
    @State private var likesCount = 0
    @State private var isTogglingLike = false
    
    var isOwnComment: Bool {
        authManager.currentUser?.id == comment.userId
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let imageURLString = comment.userImageURL, let imageURL = URL(string: imageURLString) {
                CustomAsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                    default:
                        defaultAvatar
                    }
                }
            } else {
                defaultAvatar
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let username = comment.username {
                        Text("@\(username)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    } else {
                        Text("User")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                    
                    Spacer()
                    
                    Button(action: toggleLike) {
                        HStack(spacing: 4) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 12))
                                .foregroundColor(isLiked ? .red : .white.opacity(0.4))
                            
                            if likesCount > 0 {
                                Text("\(likesCount)")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                    .disabled(isTogglingLike || authManager.currentUser == nil)
                    
                    if isOwnComment {
                        Button(action: { showDeleteConfirmation = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                
                Text(comment.content)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog("Delete Comment", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await onDelete()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this comment?")
        }
        .task {
            await loadLikeStatus()
        }
        .onAppear {
            likesCount = initialLikesCount
        }
    }
    
    private var defaultAvatar: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            )
    }
    
    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: comment.createdAt, relativeTo: Date())
    }
    
    private func loadLikeStatus() async {
        do {
            likesCount = try await firebaseService.getCommentLikesCount(reviewId: reviewId, commentId: comment.id)
            
            if let userId = authManager.currentUser?.id {
                isLiked = try await firebaseService.hasUserLikedComment(reviewId: reviewId, commentId: comment.id, userId: userId)
            }
        } catch {
            print("Error loading comment like status: \(error)")
        }
    }
    
    private func toggleLike() {
        guard let user = authManager.currentUser else { return }
        
        isTogglingLike = true
        
        Task {
            do {
                if isLiked {
                    try await firebaseService.unlikeComment(reviewId: reviewId, commentId: comment.id, userId: user.id)
                    await MainActor.run {
                        isLiked = false
                        likesCount = max(0, likesCount - 1)
                    }
                } else {
                    try await firebaseService.likeComment(reviewId: reviewId, commentId: comment.id, user: user)
                    await MainActor.run {
                        isLiked = true
                        likesCount += 1
                    }
                }
            } catch {
                print("Error toggling comment like: \(error)")
            }
            
            await MainActor.run {
                isTogglingLike = false
            }
        }
    }
}

#Preview {
    NavigationView {
        ReviewsListView(
            spotifyId: "0V3wPSX9ygBnCm8psDIegu",
            itemName: "Anti-Hero",
            artistName: "Taylor Swift",
            imageURL: nil,
            reviewType: .track
        )
    }
    .environmentObject(AuthenticationManager())
    .environmentObject(FirebaseService())
    .environmentObject(BuddyManager())
}
