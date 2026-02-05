//
//  SendMusicView.swift
//  Resonance
//
//  Created by Claude on 2/4/26.
//

import SwiftUI

/// Information about the music item to be sent
struct MusicItemToSend {
    let spotifyId: String
    let itemType: MusicRecommendation.ItemType
    let name: String
    let artistName: String?
    let imageURL: URL?
}

struct SendMusicView: View {
    let musicItem: MusicItemToSend
    
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var buddyManager: BuddyManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedBuddy: Buddy?
    @State private var message: String = ""
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    
    private let maxMessageLength = 100
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Music Item Preview
                        musicPreview
                        
                        // Buddy Selection
                        buddySelectionSection
                        
                        // Message Input
                        messageSection
                        
                        // Send Button
                        sendButton
                    }
                    .padding()
                }
            }
            .navigationTitle("send to buddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Sent!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                if let buddy = selectedBuddy {
                    Text("Sent \(musicItem.name) to @\(buddy.username ?? buddy.displayName)")
                }
            }
            .onAppear {
                // Initialize buddy manager if needed
                buddyManager.initialize(firebaseService: firebaseService)
                if let userId = authManager.currentUser?.id {
                    buddyManager.setUserId(userId)
                }
            }
        }
    }
    
    // MARK: - Music Preview
    
    private var musicPreview: some View {
        HStack(spacing: 16) {
            // Album/Artist Art
            AsyncImage(url: musicItem.imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 80, height: 80)
            .clipShape(musicItem.itemType == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(musicItem.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                if let artistName = musicItem.artistName {
                    Text(artistName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                
                Text(itemTypeLabel)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var itemTypeLabel: String {
        switch musicItem.itemType {
        case .track: return "Song"
        case .album: return "Album"
        case .artist: return "Artist"
        }
    }
    
    // MARK: - Buddy Selection
    
    private var buddySelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("send to")
                .font(.headline)
                .foregroundColor(.white)
            
            if buddyManager.buddies.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No buddies yet")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Add buddies to send them music")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(buddyManager.buddies) { buddy in
                        BuddySelectRow(
                            buddy: buddy,
                            isSelected: selectedBuddy?.id == buddy.id,
                            onSelect: { selectedBuddy = buddy }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Message Section
    
    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("message (optional)")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(message.count)/\(maxMessageLength)")
                    .font(.caption)
                    .foregroundColor(message.count > maxMessageLength ? .red : .white.opacity(0.5))
            }
            
            TextField("Add a note...", text: $message, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(.white)
                .lineLimit(3...5)
                .onChange(of: message) { _, newValue in
                    if newValue.count > maxMessageLength {
                        message = String(newValue.prefix(maxMessageLength))
                    }
                }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Send Button
    
    private var sendButton: some View {
        Button(action: sendRecommendation) {
            HStack {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                    Text("Send")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                selectedBuddy != nil && !isSending
                    ? Color(red: 0.11, green: 0.73, blue: 0.33)
                    : Color.gray.opacity(0.3)
            )
            .cornerRadius(12)
        }
        .disabled(selectedBuddy == nil || isSending)
    }
    
    // MARK: - Send Logic
    
    private func sendRecommendation() {
        guard let currentUser = authManager.currentUser,
              let buddy = selectedBuddy else { return }
        
        isSending = true
        
        Task {
            do {
                // Note: We skip the duplicate check to avoid complex Firestore query permissions
                // The worst case is sending the same item twice, which is acceptable
                
                // Create recommendation
                let recommendation = MusicRecommendation(
                    id: MusicRecommendation.makeId(
                        senderId: currentUser.id,
                        receiverId: buddy.id,
                        spotifyId: musicItem.spotifyId
                    ),
                    senderId: currentUser.id,
                    receiverId: buddy.id,
                    senderUsername: currentUser.username,
                    senderDisplayName: currentUser.displayName,
                    senderImageURL: currentUser.imageURL,
                    receiverUsername: buddy.username,
                    receiverDisplayName: buddy.displayName,
                    receiverImageURL: buddy.imageURL,
                    spotifyId: musicItem.spotifyId,
                    itemType: musicItem.itemType,
                    itemName: musicItem.name,
                    artistName: musicItem.artistName,
                    imageURL: musicItem.imageURL?.absoluteString,
                    message: message.isEmpty ? nil : message,
                    sentAt: Date(),
                    status: .pending,
                    receiverRatingId: nil
                )
                
                try await firebaseService.sendMusicRecommendation(recommendation)
                
                isSending = false
                showSuccess = true
            } catch {
                errorMessage = "Failed to send: \(error.localizedDescription)"
                isSending = false
            }
        }
    }
}

// MARK: - Buddy Select Row

struct BuddySelectRow: View {
    let buddy: Buddy
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Profile Image
                if let imageURLString = buddy.imageURL,
                   let imageURL = URL(string: imageURLString) {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    if let username = buddy.username {
                        Text("@\(username)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    
                    Text(buddy.displayName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? Color(red: 0.11, green: 0.73, blue: 0.33) : .white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color(red: 0.11, green: 0.73, blue: 0.33) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SendMusicView(musicItem: MusicItemToSend(
        spotifyId: "test123",
        itemType: .track,
        name: "Test Song",
        artistName: "Test Artist",
        imageURL: nil
    ))
    .environmentObject(FirebaseService())
    .environmentObject(AuthenticationManager())
    .environmentObject(BuddyManager())
}
