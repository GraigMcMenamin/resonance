//
//  RatingSheet.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 1/12/26.
//

import SwiftUI

struct RatingSheet: View {
    let item: RatableItem
    @ObservedObject var ratingsManager: RatingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @Environment(\.dismiss) var dismiss
    
    @State private var percentage: Double = 50
    @State private var hasExistingRating = false
    @State private var communityAverage: Double?
    @State private var ratingCount: Int = 0
    
    // Review states
    @State private var reviewContent: String = ""
    @State private var selectedLength: Review.ReviewLength = .short
    @State private var existingReview: Review?
    @State private var isLoadingReview = false
    @State private var isSaving = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    
    private let shortCharacterLimit = 149
    private let minLongCharacters = 150
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18)
                    .ignoresSafeArea()
                
                if isLoadingReview {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Item Info
                            itemInfoSection
                            
                            // Rating Percentage
                            ratingPercentageSection
                            
                            // Slider
                            sliderSection
                            
                            // Review Section (Optional)
                            reviewSection
                            
                            // Error Message
                            if let error = errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal)
                            }
                            
                            // Save Button or Guest Message
                            saveOrGuestSection
                            
                            // Delete Button (if editing existing)
                            if existingReview != nil {
                                deleteButton
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle(existingReview != nil ? "Edit Rating" : "Rate & Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Delete Rating & Review", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteRatingAndReview()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete your rating and review?")
            }
        }
        .onAppear {
            loadExistingRating()
            loadCommunityRating()
        }
        .task {
            // Check legacy reviews collection for any existing review content
            await loadExistingReviewFromLegacy()
        }
    }
    
    // MARK: - Item Info Section
    
    private var itemInfoSection: some View {
        VStack(spacing: 12) {
            CustomAsyncImage(url: itemImageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 100, height: 100)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipShape(itemShape)
                case .failure:
                    ZStack {
                        Color.gray.opacity(0.2)
                        Image(systemName: itemIconName)
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(itemShape)
                @unknown default:
                    Color.gray
                        .frame(width: 100, height: 100)
                        .clipShape(itemShape)
                }
            }
            .shadow(radius: 8)
            
            VStack(spacing: 4) {
                Text(itemName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                if let subtitle = itemSubtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.top)
    }
    
    // MARK: - Rating Percentage Section
    
    private var ratingPercentageSection: some View {
        VStack(spacing: 8) {
            Text("\(Int(percentage))%")
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundColor(percentageColor)
            
            Text(ratingLabel)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            // Average Rating
            if let average = communityAverage, ratingCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                    Text("Average: \(Int(average))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("(\(ratingCount))")
                        .font(.caption2)
                }
                .foregroundColor(colorForPercentage(average))
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Slider Section
    
    private var sliderSection: some View {
        VStack(spacing: 8) {
            Slider(value: $percentage, in: 0...100, step: 1)
                .tint(percentageColor)
                .disabled(authManager.isGuestMode)
            
            HStack {
                Text("0%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("100%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Review Section
    
    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack {
                Text("Add a Review")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("(optional)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal)
            
            // Length Toggle
            Picker("Review Length", selection: $selectedLength) {
                Text("Short").tag(Review.ReviewLength.short)
                Text("Long").tag(Review.ReviewLength.long)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: selectedLength) { _, newValue in
                if newValue == .short && reviewContent.count >= minLongCharacters {
                    reviewContent = String(reviewContent.prefix(shortCharacterLimit))
                }
            }
            
            // Character count
            HStack {
                if selectedLength == .short {
                    Text("\(reviewContent.count)/\(shortCharacterLimit)")
                        .font(.caption)
                        .foregroundColor(reviewContent.count > shortCharacterLimit ? .red : .white.opacity(0.5))
                } else {
                    Text("\(reviewContent.count) characters (min \(minLongCharacters))")
                        .font(.caption)
                        .foregroundColor(reviewContent.count < minLongCharacters && !reviewContent.isEmpty ? .orange : .white.opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal)
            
            // Text Editor
            ZStack(alignment: .topLeading) {
                if reviewContent.isEmpty {
                    Text("Share your thoughts... (optional)")
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }
                
                TextEditor(text: $reviewContent)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(.white)
                    .padding(8)
                    .onChange(of: reviewContent) { _, newValue in
                        if selectedLength == .short && newValue.count > shortCharacterLimit {
                            reviewContent = String(newValue.prefix(shortCharacterLimit))
                        }
                    }
            }
            .frame(height: selectedLength == .short ? 100 : 150)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(reviewBorderColor, lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
    
    // MARK: - Save or Guest Section
    
    private var saveOrGuestSection: some View {
        Group {
            if authManager.isGuestMode {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Sign in to save your ratings")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    Button(action: {
                        dismiss()
                        authManager.exitGuestMode()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                            Text("Sign in with Spotify")
                        }
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(red: 0.11, green: 0.73, blue: 0.33))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
            } else {
                Button(action: {
                    Task { await saveRatingAndReview() }
                }) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(existingReview != nil ? "Update" : "Save")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSave ? percentageColor : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(!canSave || isSaving)
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Delete Button
    
    private var deleteButton: some View {
        Button(action: {
            showingDeleteConfirmation = true
        }) {
            HStack {
                Image(systemName: "trash")
                Text("Delete Rating & Review")
            }
            .font(.subheadline)
            .foregroundColor(.red)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.1))
            )
        }
        .padding(.top, 8)
    }
    
    // MARK: - Computed Properties
    
    private var itemImageURL: URL? {
        switch item {
        case .artist(let artist): return artist.imageURL
        case .album(let album): return album.imageURL
        case .track(let track): return track.imageURL
        }
    }
    
    private var itemName: String {
        switch item {
        case .artist(let artist): return artist.name
        case .album(let album): return album.name
        case .track(let track): return track.name
        }
    }
    
    private var itemSubtitle: String? {
        switch item {
        case .artist: return nil
        case .album(let album): return album.artistNames
        case .track(let track): return track.artistNames
        }
    }
    
    private var itemShape: some Shape {
        switch item {
        case .artist: return AnyShape(Circle())
        case .album, .track: return AnyShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var itemIconName: String {
        switch item {
        case .artist: return "music.mic"
        case .album: return "square.stack"
        case .track: return "music.note"
        }
    }
    
    private var reviewType: Review.ReviewType {
        switch item {
        case .artist: return .artist
        case .album: return .album
        case .track: return .track
        }
    }
    
    private var percentageColor: Color {
        colorForPercentage(percentage)
    }
    
    private func colorForPercentage(_ value: Double) -> Color {
        switch value {
        case 0..<40:
            return .red
        case 40..<60:
            return .orange
        case 60..<75:
            return .yellow
        case 75..<90:
            return Color(red: 0.6, green: 0.8, blue: 0.2)
        default:
            return .green
        }
    }
    
    private var ratingLabel: String {
        switch percentage {
        case 0..<40:
            return "Poor"
        case 40..<60:
            return "Average"
        case 60..<75:
            return "Good"
        case 75..<90:
            return "Great"
        default:
            return "Masterpiece"
        }
    }
    
    private var reviewBorderColor: Color {
        let trimmed = reviewContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Color.white.opacity(0.1)
        }
        if selectedLength == .short && reviewContent.count > shortCharacterLimit {
            return .red
        } else if selectedLength == .long && reviewContent.count < minLongCharacters {
            return .orange
        }
        return .green
    }
    
    private var canSave: Bool {
        // Rating is always required (already have percentage)
        // Review is optional
        let trimmedReview = reviewContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If there's no review content, we can save (rating only)
        if trimmedReview.isEmpty {
            return true
        }
        
        // If there is review content, it must meet length requirements
        if selectedLength == .short {
            return reviewContent.count <= shortCharacterLimit
        } else {
            return reviewContent.count >= minLongCharacters
        }
    }
    
    // MARK: - Actions
    
    private func loadExistingRating() {
        guard let userId = authManager.currentUser?.id else { return }
        let ratingId = UserRating.makeId(userId: userId, spotifyId: item.id)
        
        if let existingRating = ratingsManager.getRating(for: ratingId) {
            percentage = Double(existingRating.percentage)
            hasExistingRating = true
            
            // Load review content from rating if it exists
            if let content = existingRating.reviewContent, !content.isEmpty {
                reviewContent = content
                // Determine length based on content
                selectedLength = content.count < 150 ? .short : .long
            }
        }
    }
    
    private func loadCommunityRating() {
        communityAverage = ratingsManager.getAverageRating(for: item.id)
        ratingCount = ratingsManager.getRatingCount(for: item.id)
    }
    
    private func loadExistingReviewFromLegacy() async {
        // Legacy: Check old reviews collection for existing review content
        // This can be removed once all reviews are migrated to ratings collection
        guard let userId = authManager.currentUser?.id else { return }
        guard reviewContent.isEmpty else { return } // Already loaded from rating
        
        isLoadingReview = true
        
        do {
            existingReview = try await firebaseService.getUserReview(userId: userId, spotifyId: item.id)
            
            if let review = existingReview {
                if let content = review.content, !content.isEmpty {
                    reviewContent = content
                }
                if let length = review.reviewLength {
                    selectedLength = length
                }
            }
        } catch {
            print("Error loading existing review from legacy: \(error)")
        }
        
        isLoadingReview = false
    }
    
    private func saveRatingAndReview() async {
        guard let user = authManager.currentUser else { return }
        
        isSaving = true
        errorMessage = nil
        
        let trimmedContent = reviewContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasReview = !trimmedContent.isEmpty
        
        // Create the rating with optional review content embedded
        var rating = UserRating(
            id: UserRating.makeId(userId: user.id, spotifyId: item.id),
            spotifyId: item.id,
            userId: user.id,
            type: ratingType,
            name: itemName,
            artistName: itemSubtitle,
            imageURL: itemImageURL?.absoluteString,
            percentage: Int(percentage),
            dateRated: Date(),
            userName: user.displayName,
            username: user.username,
            userImageURL: user.imageURL,
            reviewContent: hasReview ? trimmedContent : nil,
            reviewDateCreated: hasReview ? (existingReview?.dateCreated ?? Date()) : nil,
            reviewDateUpdated: (hasReview && existingReview != nil) ? Date() : nil
        )
        
        do {
            // Save the rating (with embedded review content)
            await ratingsManager.addOrUpdateRating(rating)
            
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
        
        isSaving = false
    }
    
    private func deleteRatingAndReview() async {
        guard let user = authManager.currentUser else { return }
        
        isSaving = true
        
        do {
            // Delete the rating (which now includes review content)
            let ratingId = UserRating.makeId(userId: user.id, spotifyId: item.id)
            await ratingsManager.deleteRating(id: ratingId)
            
            dismiss()
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
        
        isSaving = false
    }
    
    private var ratingType: UserRating.RatingType {
        switch item {
        case .artist: return .artist
        case .album: return .album
        case .track: return .track
        }
    }
}

// MARK: - AnyShape Helper

struct AnyShape: Shape {
    private let _path: @Sendable (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        _path = { rect in
            shape.path(in: rect)
        }
    }
    
    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

#Preview {
    RatingSheet(
        item: .artist(SpotifyArtist(
            id: "1",
            name: "Taylor Swift",
            images: nil,
            genres: ["pop"],
            popularity: 95
        )),
        ratingsManager: RatingsManager(firebaseService: FirebaseService())
    )
    .environmentObject(AuthenticationManager())
    .environmentObject(FirebaseService())
}
