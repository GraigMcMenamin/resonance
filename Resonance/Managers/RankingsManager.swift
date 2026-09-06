//
//  RankingsManager.swift
//  Resonance
//
//  Created by Mcmenamin, Graig on 9/5/26.
//

import Foundation
import Combine

@MainActor
class RankingsManager: ObservableObject {
    @Published var allRankings: [UserRanking] = [] // All users' rankings
    @Published var errorMessage: String?
    
    private let firebaseService: FirebaseService
    private var cancellables = Set<AnyCancellable>()
    
    init(firebaseService: FirebaseService) {
        self.firebaseService = firebaseService
        setupFirebaseListener()
    }
    
    private func setupFirebaseListener() {
        firebaseService.$allRankings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rankings in
                self?.allRankings = rankings
            }
            .store(in: &cancellables)
        
        firebaseService.startListeningToAllRankings()
    }
    
    // MARK: - CRUD Operations
    
    func addOrUpdateRanking(_ ranking: UserRanking) async {
        do {
            try await firebaseService.saveRanking(ranking)
            if let index = allRankings.firstIndex(where: { $0.id == ranking.id }) {
                allRankings[index] = ranking
            } else {
                allRankings.append(ranking)
            }
        } catch {
            errorMessage = "Failed to save ranking: \(error.localizedDescription)"
            print("Error saving ranking to Firebase: \(error)")
        }
    }
    
    func deleteRanking(id: String) async {
        do {
            try await firebaseService.deleteRanking(id: id)
            allRankings.removeAll { $0.id == id }
        } catch {
            errorMessage = "Failed to delete ranking: \(error.localizedDescription)"
            print("Error deleting ranking from Firebase: \(error)")
        }
    }
    
    func getRanking(id: String) -> UserRanking? {
        allRankings.first { $0.id == id }
    }
    
    // MARK: - Filtering
    
    func rankings(forUserId userId: String) -> [UserRanking] {
        allRankings.filter { $0.userId == userId }
            .sorted { ($0.dateUpdated ?? $0.dateCreated) > ($1.dateUpdated ?? $1.dateCreated) }
    }
}
