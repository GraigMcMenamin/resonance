//
//  BuddyManager.swift
//  Resonance
//
//  Created by Claude on 1/23/26.
//

import SwiftUI
import Combine

@MainActor
class BuddyManager: ObservableObject {
    @Published var buddies: [Buddy] = []
    @Published var pendingRequests: [BuddyRequest] = []
    @Published var sentRequests: [BuddyRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var firebaseService: FirebaseService!
    private var currentUserId: String?
    
    nonisolated init() {}
    
    func initialize(firebaseService: FirebaseService) {
        self.firebaseService = firebaseService
    }
    
    func setUserId(_ userId: String?) {
        self.currentUserId = userId
        if let userId = userId {
            Task {
                await loadAllBuddyData(userId: userId)
            }
        } else {
            buddies = []
            pendingRequests = []
            sentRequests = []
        }
    }
    
    func loadAllBuddyData(userId: String) async {
        isLoading = true
        
        do {
            async let buddiesTask = firebaseService.getBuddies(forUserId: userId)
            async let pendingTask = firebaseService.getPendingBuddyRequests(forUserId: userId)
            async let sentTask = firebaseService.getSentBuddyRequests(fromUserId: userId)
            
            let (loadedBuddies, loadedPending, loadedSent) = try await (buddiesTask, pendingTask, sentTask)
            
            buddies = loadedBuddies
            pendingRequests = loadedPending
            sentRequests = loadedSent.filter { $0.status == .pending }
            
            isLoading = false
        } catch {
            print("Error loading buddy data: \(error)")
            errorMessage = "Failed to load buddies"
            isLoading = false
        }
    }
    
    func sendBuddyRequest(from fromUser: AppUser, to toUser: AppUser) async {
        do {
            try await firebaseService.sendBuddyRequest(from: fromUser, to: toUser)
            // Refresh sent requests
            if let userId = currentUserId {
                let sent = try await firebaseService.getSentBuddyRequests(fromUserId: userId)
                sentRequests = sent.filter { $0.status == .pending }
            }
        } catch {
            print("Error sending buddy request: \(error)")
            errorMessage = "Failed to send buddy request"
        }
    }
    
    func acceptRequest(_ request: BuddyRequest) async {
        do {
            try await firebaseService.acceptBuddyRequest(request)
            // Remove from pending and refresh buddies
            pendingRequests.removeAll { $0.id == request.id }
            if let userId = currentUserId {
                buddies = try await firebaseService.getBuddies(forUserId: userId)
            }
        } catch {
            print("Error accepting buddy request: \(error)")
            errorMessage = "Failed to accept request"
        }
    }
    
    func rejectRequest(_ request: BuddyRequest) async {
        do {
            try await firebaseService.rejectBuddyRequest(request)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            print("Error rejecting buddy request: \(error)")
            errorMessage = "Failed to reject request"
        }
    }
    
    func removeBuddy(buddyId: String) async {
        guard let userId = currentUserId else { return }
        
        do {
            try await firebaseService.removeBuddy(userId: userId, buddyId: buddyId)
            buddies.removeAll { $0.id == buddyId }
        } catch {
            print("Error removing buddy: \(error)")
            errorMessage = "Failed to remove buddy"
        }
    }
    
    func checkBuddyStatus(with otherUserId: String) async -> FirebaseService.BuddyStatus {
        guard let userId = currentUserId else { return .notBuddies }
        
        do {
            return try await firebaseService.checkBuddyStatus(userId: userId, otherUserId: otherUserId)
        } catch {
            print("Error checking buddy status: \(error)")
            return .notBuddies
        }
    }
    
    func refresh() async {
        guard let userId = currentUserId else { return }
        await loadAllBuddyData(userId: userId)
    }
}
