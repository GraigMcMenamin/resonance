//
//  BuddiesListView.swift
//  Resonance
//
//  Created by Claude on 1/23/26.
//

import SwiftUI

struct BuddiesListView: View {
    let buddies: [Buddy]
    let title: String
    
    init(buddies: [Buddy], title: String = "Buddies") {
        self.buddies = buddies
        self.title = title
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.15, green: 0.08, blue: 0.18)
                .ignoresSafeArea()
            
            if buddies.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("No buddies yet")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("Search for users to add buddies")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.4))
                }
            } else {
                List {
                    ForEach(buddies) { buddy in
                        NavigationLink(destination: buddyProfileDestination(buddy: buddy)) {
                            buddyRow(buddy: buddy)
                        }
                        .listRowBackground(Color.white.opacity(0.05))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    @ViewBuilder
    private func buddyRow(buddy: Buddy) -> some View {
        HStack(spacing: 12) {
            // Profile Image
            if let imageURLString = buddy.imageURL, let imageURL = URL(string: imageURLString) {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.5))
                        )
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
                if let username = buddy.username {
                    Text("@\(username)")
                        .font(.headline)
                        .foregroundColor(.white)
                } else {
                    Text("User")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func buddyProfileDestination(buddy: Buddy) -> some View {
        let user = AppUser(
            id: buddy.id,
            firebaseUID: buddy.id,
            username: buddy.username,
            usernameLowercase: buddy.username?.lowercased(),
            imageURL: buddy.imageURL
        )
        OtherUserProfileView(user: user)
    }
}

#Preview {
    NavigationView {
        BuddiesListView(buddies: [])
    }
}
