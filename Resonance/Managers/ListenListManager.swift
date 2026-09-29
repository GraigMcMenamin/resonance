//
//  ListenListManager.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 9/27/26.
//

import Foundation
import Combine

/// Manages the current user's private "listen list" (artists/albums/songs they
/// intend to listen to, each with a 1-10 priority). Mirrors MailboxManager's
/// fetch-on-demand pattern rather than a real-time listener since this data
/// is private and low-volume.
@MainActor
class ListenListManager: ObservableObject {
    @Published var items: [ListenListItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var firebaseService: FirebaseService?
    private var currentUserId: String?

    func initialize(firebaseService: FirebaseService) {
        self.firebaseService = firebaseService
    }

    func setUserId(_ userId: String?) {
        currentUserId = userId
        if let userId = userId {
            Task { await refresh(userId: userId) }
        } else {
            items = []
        }
    }

    func refresh() async {
        guard let userId = currentUserId else { return }
        await refresh(userId: userId)
    }

    private func refresh(userId: String) async {
        guard let firebaseService = firebaseService else { return }
        isLoading = true
        do {
            items = try await firebaseService.getListenList(userId: userId)
        } catch {
            errorMessage = "Failed to load listen list: \(error.localizedDescription)"
            print("[ListenListManager] Error loading listen list: \(error)")
        }
        isLoading = false
    }

    func contains(spotifyId: String) -> Bool {
        items.contains { $0.spotifyId == spotifyId }
    }

    func item(for spotifyId: String) -> ListenListItem? {
        items.first { $0.spotifyId == spotifyId }
    }

    /// Adds a new item or updates an existing one. `priority` is optional — pass `nil` to leave it unset.
    /// Returns `false` (and sets `errorMessage`) if the write couldn't be made — e.g. the
    /// manager doesn't have a userId yet — so callers can avoid assuming success.
    @discardableResult
    func addOrUpdate(spotifyId: String, type: UserRating.RatingType, name: String, artistName: String?, imageURL: String?, priority: Int?) async -> Bool {
        guard let userId = currentUserId, let firebaseService = firebaseService else {
            errorMessage = "Couldn't save — please try again in a moment."
            return false
        }
        let existing = item(for: spotifyId)
        let newItem = ListenListItem(
            spotifyId: spotifyId,
            type: type,
            name: name,
            artistName: artistName,
            imageURL: imageURL,
            priority: priority.map { min(max($0, 0), 10) },
            dateAdded: existing?.dateAdded ?? Date()
        )
        do {
            try await firebaseService.saveListenListItem(newItem, userId: userId)
            if let index = items.firstIndex(where: { $0.spotifyId == spotifyId }) {
                items[index] = newItem
            } else {
                items.append(newItem)
            }
            return true
        } catch {
            errorMessage = "Failed to save item: \(error.localizedDescription)"
            print("[ListenListManager] Error saving item: \(error)")
            return false
        }
    }

    @discardableResult
    func remove(spotifyId: String) async -> Bool {
        guard let userId = currentUserId, let firebaseService = firebaseService else {
            errorMessage = "Couldn't remove — please try again in a moment."
            return false
        }
        do {
            try await firebaseService.deleteListenListItem(spotifyId: spotifyId, userId: userId)
            items.removeAll { $0.spotifyId == spotifyId }
            return true
        } catch {
            errorMessage = "Failed to remove item: \(error.localizedDescription)"
            print("[ListenListManager] Error removing item: \(error)")
            return false
        }
    }

    // MARK: - Filtering & Sorting

    enum Filter: String, CaseIterable {
        case all, artists, albums, songs

        var label: String { rawValue }
    }

    enum SortOrder: String, CaseIterable {
        case dateAdded = "date added"
        case priority = "priority"
    }

    func filteredSorted(filter: Filter, sort: SortOrder) -> [ListenListItem] {
        Self.apply(filter: filter, sort: sort, to: items)
    }

    /// Shared filter/sort logic — also used to display other users' (read-only) listen lists.
    static func apply(filter: Filter, sort: SortOrder, to items: [ListenListItem]) -> [ListenListItem] {
        let filtered: [ListenListItem]
        switch filter {
        case .all: filtered = items
        case .artists: filtered = items.filter { $0.type == .artist }
        case .albums: filtered = items.filter { $0.type == .album }
        case .songs: filtered = items.filter { $0.type == .track }
        }

        switch sort {
        case .dateAdded:
            return filtered.sorted { $0.dateAdded > $1.dateAdded }
        case .priority:
            return filtered.sorted { lhs, rhs in
                switch (lhs.priority, rhs.priority) {
                case let (l?, r?):
                    return l != r ? l > r : lhs.dateAdded > rhs.dateAdded
                case (nil, nil):
                    return lhs.dateAdded > rhs.dateAdded
                case (nil, _):
                    return false // items without a priority sort after prioritized ones
                case (_, nil):
                    return true
                }
            }
        }
    }
}
