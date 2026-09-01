import Foundation
import Combine

public final class ProfileStorage: ObservableObject {
    public static let shared = ProfileStorage()
    
    @Published public var profiles: [ControllerProfile] = []
    @Published public var activeProfileId: UUID?
    
    private let fileManager = FileManager.default
    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let singleSenseDir = appSupport.appendingPathComponent("SingleSense", isDirectory: true)
        if !fileManager.fileExists(atPath: singleSenseDir.path) {
            try? fileManager.createDirectory(at: singleSenseDir, withIntermediateDirectories: true)
        }
        return singleSenseDir
    }
    
    private var profilesFileURL: URL {
        storageDirectory.appendingPathComponent("profiles.json")
    }
    
    private init() {
        loadProfiles()
    }
    
    public func loadProfiles() {
        if fileManager.fileExists(atPath: profilesFileURL.path),
           let data = try? Data(contentsOf: profilesFileURL),
           let decoded = try? JSONDecoder().decode([ControllerProfile].self, from: data),
           !decoded.isEmpty {
            self.profiles = decoded
            self.activeProfileId = decoded.first?.id
        } else {
            // Populate defaults
            let defaults = DefaultProfiles.createDefaults()
            self.profiles = defaults
            self.activeProfileId = defaults.first?.id
            saveProfiles()
        }
    }
    
    public func saveProfiles() {
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: profilesFileURL)
        } catch {
            print("[SingleSense] Failed to save profiles: \(error)")
        }
    }
    
    public func addProfile(_ profile: ControllerProfile) {
        profiles.append(profile)
        saveProfiles()
    }
    
    public func updateProfile(_ profile: ControllerProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            var updated = profile
            updated.updatedAt = Date()
            profiles[index] = updated
            saveProfiles()
        }
    }
    
    public func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles.first?.id
        }
        saveProfiles()
    }
    
    public func duplicateProfile(_ profile: ControllerProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) (Copy)"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        profiles.append(copy)
        saveProfiles()
    }
}
