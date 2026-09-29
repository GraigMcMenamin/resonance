//
//  OtherUserListenListView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 9/27/26.
//
//  Read-only view of another user's public listen list.
//

import SwiftUI

struct OtherUserListenListView: View {
    let userId: String
    let username: String?

    @EnvironmentObject var firebaseService: FirebaseService

    @State private var items: [ListenListItem] = []
    @State private var isLoading = true
    @State private var filter: ListenListManager.Filter = .all
    @State private var sort: ListenListManager.SortOrder = .dateAdded

    private var displayedItems: [ListenListItem] {
        ListenListManager.apply(filter: filter, sort: sort, to: items)
    }

    var body: some View {
        VStack(spacing: 12) {
            controlsBar

            if isLoading {
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            } else if displayedItems.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(displayedItems) { item in
                        NavigationLink(destination: destinationView(for: item)) {
                            ListenListRow(item: item)
                        }
                        .listRowBackground(Color.black)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(username.map { "@\($0) listen list" } ?? "listen list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                sortMenu
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        items = (try? await firebaseService.getListenList(userId: userId)) ?? []
        isLoading = false
    }

    private var controlsBar: some View {
        VStack(spacing: 10) {
            Picker("filter", selection: $filter) {
                ForEach(ListenListManager.Filter.allCases, id: \.self) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("\(displayedItems.count) item\(displayedItems.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))

                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var sortMenu: some View {
        Menu {
            Picker("sort", selection: $sort) {
                ForEach(ListenListManager.SortOrder.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text(sort.rawValue)
            }
            .font(.subheadline)
            .foregroundColor(.white)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            Text("Nothing here yet")
                .font(.headline)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
    }

    @ViewBuilder
    private func destinationView(for item: ListenListItem) -> some View {
        switch item.type {
        case .artist:
            ArtistDetailView(
                artistId: item.spotifyId,
                artistName: item.name,
                artistImageURL: item.imageURL.flatMap { URL(string: $0) }
            )
        case .album:
            AlbumDetailView(
                albumId: item.spotifyId,
                albumName: item.name,
                artistName: item.artistName ?? "",
                imageURL: item.imageURL.flatMap { URL(string: $0) }
            )
        case .track:
            SongDetailView(
                trackId: item.spotifyId,
                trackName: item.name,
                artistName: item.artistName ?? "",
                albumName: nil,
                albumId: nil,
                imageURL: item.imageURL.flatMap { URL(string: $0) }
            )
        }
    }
}
