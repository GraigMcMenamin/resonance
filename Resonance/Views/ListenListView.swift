//
//  ListenListView.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 9/27/26.
//
//  "Listen list" — a private list of artists/albums/songs the user is meaning
//  to listen to, each with a 1-10 priority. Filterable by type, sortable by
//  date added or priority.
//

import SwiftUI

struct ListenListView: View {
    @EnvironmentObject var listenListManager: ListenListManager
    @EnvironmentObject var ratingsManager: RatingsManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var firebaseService: FirebaseService
    @EnvironmentObject var notificationManager: NotificationManager

    @State private var filter: ListenListManager.Filter = .all
    @State private var sort: ListenListManager.SortOrder = .dateAdded
    @State private var itemPendingReviewPrompt: ListenListItem?
    @State private var selectedRatableItem: RatableItem?

    private var displayedItems: [ListenListItem] {
        listenListManager.filteredSorted(filter: filter, sort: sort)
    }

    var body: some View {
        VStack(spacing: 12) {
            controlsBar

            if listenListManager.isLoading && listenListManager.items.isEmpty {
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            } else if displayedItems.isEmpty {
                emptyState
            } else {
                List {
                    Section(footer: swipeHintFooter) {
                        ForEach(displayedItems) { item in
                            NavigationLink(destination: destinationView(for: item)) {
                                ListenListRow(item: item)
                            }
                            .listRowBackground(Color.black)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    itemPendingReviewPrompt = item
                                } label: {
                                    Label("listened", systemImage: "checkmark.circle.fill")
                                }
                                .tint(Color(red: 0.6, green: 0.4, blue: 0.8))
                            }
                        }
                    }
                    .listSectionSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("listen list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                sortMenu
            }
        }
        .task { await listenListManager.refresh() }
        .refreshable { await listenListManager.refresh() }
        .alert(
            "Review \(itemPendingReviewPrompt?.name ?? "this")?",
            isPresented: Binding(get: { itemPendingReviewPrompt != nil }, set: { if !$0 { itemPendingReviewPrompt = nil } })
        ) {
            Button("yes") {
                if let item = itemPendingReviewPrompt {
                    selectedRatableItem = ratableItem(for: item)
                    Task { await listenListManager.remove(spotifyId: item.spotifyId) }
                }
                itemPendingReviewPrompt = nil
            }
            Button("no") {
                if let item = itemPendingReviewPrompt {
                    Task { await listenListManager.remove(spotifyId: item.spotifyId) }
                }
                itemPendingReviewPrompt = nil
            }
        }
        .sheet(item: $selectedRatableItem) { item in
            RatingSheet(item: item, ratingsManager: ratingsManager)
                .environmentObject(authManager)
                .environmentObject(firebaseService)
        }
    }

    /// Builds a minimal RatableItem from the listen list's denormalized fields so the
    /// standard RatingSheet can be reused without re-fetching the full Spotify object.
    private func ratableItem(for item: ListenListItem) -> RatableItem {
        let images: [SpotifyImage]? = item.imageURL.map { [SpotifyImage(url: $0, height: nil, width: nil)] }
        switch item.type {
        case .artist:
            return .artist(SpotifyArtist(id: item.spotifyId, name: item.name, images: images, genres: nil, popularity: nil))
        case .album:
            return .album(SpotifyAlbum(
                id: item.spotifyId,
                name: item.name,
                artists: [SpotifyArtistSimple(id: "", name: item.artistName ?? "")],
                images: images,
                releaseDate: nil,
                totalTracks: nil
            ))
        case .track:
            return .track(SpotifyTrack(
                id: item.spotifyId,
                name: item.name,
                artists: [SpotifyArtistSimple(id: "", name: item.artistName ?? "")],
                album: nil,
                durationMs: nil,
                popularity: nil
            ))
        }
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
            Text("your listen list is empty")
                .font(.headline)
                .foregroundColor(.white.opacity(0.6))
            Text("(it's a to do list but for listening)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))

            Button(action: { notificationManager.pendingDeepLink = .searchTab }) {
                Text("tap to search for music to add")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.75, green: 0.55, blue: 0.95))
                    .underline()
            }
            .padding(.top, 4)

            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
    }

    /// Shown below the list rows (as a Section footer) — with few items it lands in view
    /// naturally; once enough items fill the screen it scrolls out of the immediate view.
    private var swipeHintFooter: some View {
        Text("swipe left on music once you've listened")
            .font(.caption)
            .foregroundColor(.white.opacity(0.4))
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

// MARK: - Row

struct ListenListRow: View {
    let item: ListenListItem

    private var placeholderIcon: String {
        switch item.type {
        case .artist: return "music.mic"
        case .album: return "square.stack"
        case .track: return "music.note"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            CustomAsyncImage(url: item.imageURL.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(item.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                default:
                    Image(systemName: placeholderIcon)
                        .foregroundColor(.gray)
                        .frame(width: 52, height: 52)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(item.type == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 6)))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let artistName = item.artistName {
                    Text(artistName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Text(item.dateAdded.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            HStack(spacing: 10) {
                if let priority = item.priority {
                    Text("\(priority)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                PlayInSpotifyButton(type: item.type, spotifyId: item.spotifyId)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Reusable "play in Spotify" button

/// Small green play button that opens an item directly in Spotify (falls back to web).
struct PlayInSpotifyButton: View {
    let type: UserRating.RatingType
    let spotifyId: String
    var compact: Bool = false

    private var spotifyTypeString: String {
        switch type {
        case .artist: return "artist"
        case .album: return "album"
        case .track: return "track"
        }
    }

    var body: some View {
        Button(action: open) {
            Image(systemName: "play.circle.fill")
                .font(compact ? .title3 : .system(size: 32))
                .foregroundColor(.green)
        }
        .buttonStyle(.plain)
    }

    private func open() {
        if let uri = SpotifyService.spotifyURI(type: spotifyTypeString, id: spotifyId),
           UIApplication.shared.canOpenURL(uri) {
            UIApplication.shared.open(uri)
        } else if let webURL = SpotifyService.spotifyWebURL(type: spotifyTypeString, id: spotifyId) {
            UIApplication.shared.open(webURL)
        }
    }
}

// MARK: - Add / Update Sheet (presented from Song/Album/Artist detail views)

struct AddToListenListSheet: View {
    let spotifyId: String
    let type: UserRating.RatingType
    let name: String
    let artistName: String?
    let imageURL: URL?

    @EnvironmentObject var listenListManager: ListenListManager
    @Environment(\.dismiss) var dismiss

    @State private var priority: Double
    @State private var hasPriority: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(spotifyId: String, type: UserRating.RatingType, name: String, artistName: String?, imageURL: URL?) {
        self.spotifyId = spotifyId
        self.type = type
        self.name = name
        self.artistName = artistName
        self.imageURL = imageURL
        _priority = State(initialValue: 5)
        _hasPriority = State(initialValue: false)
    }

    private var existingItem: ListenListItem? {
        listenListManager.item(for: spotifyId)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.15, green: 0.08, blue: 0.18)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    CustomAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        default:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 100, height: 100)
                        }
                    }

                    VStack(spacing: 4) {
                        Text(name)
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        if let artistName = artistName {
                            Text(artistName)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    VStack(spacing: 8) {
                        Text(hasPriority ? "priority: \(Int(priority))" : "no priority set")
                            .font(.subheadline)
                            .foregroundColor(hasPriority ? .white : .white.opacity(0.4))
                        Slider(
                            value: $priority,
                            in: 0...10,
                            step: 1,
                            onEditingChanged: { editing in
                                if editing { hasPriority = true }
                            }
                        )
                        .tint(Color(red: 0.6, green: 0.4, blue: 0.8))
                        .opacity(hasPriority ? 1 : 0.4)
                        .padding(.horizontal, 32)
                        Text("how bad you want to listen to \(name)? (optional)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                        if hasPriority {
                            Button("clear priority") { hasPriority = false }
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    Button(action: save) {
                        Text(existingItem == nil ? "add to listen list" : "update")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.6, green: 0.4, blue: 0.8))
                            .cornerRadius(12)
                    }
                    .disabled(isSaving)
                    .padding(.horizontal, 32)

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    if existingItem != nil {
                        Button(role: .destructive, action: remove) {
                            Text("remove from listen list")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                        .disabled(isSaving)
                    }

                    Spacer()
                }
                .padding(.top, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let existing = existingItem {
                    if let existingPriority = existing.priority {
                        hasPriority = true
                        priority = Double(existingPriority)
                    } else {
                        hasPriority = false
                    }
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            let success = await listenListManager.addOrUpdate(
                spotifyId: spotifyId,
                type: type,
                name: name,
                artistName: artistName,
                imageURL: imageURL?.absoluteString,
                priority: hasPriority ? Int(priority) : nil
            )
            isSaving = false
            if success {
                dismiss()
            } else {
                errorMessage = listenListManager.errorMessage ?? "Something went wrong. Please try again."
            }
        }
    }

    private func remove() {
        isSaving = true
        errorMessage = nil
        Task {
            let success = await listenListManager.remove(spotifyId: spotifyId)
            isSaving = false
            if success {
                dismiss()
            } else {
                errorMessage = listenListManager.errorMessage ?? "Something went wrong. Please try again."
            }
        }
    }
}
