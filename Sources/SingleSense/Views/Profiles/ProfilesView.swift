import SwiftUI

public struct ProfilesView: View {
    @ObservedObject var profileStorage = ProfileStorage.shared
    @ObservedObject var manager = DualSenseManager.shared
    
    @State private var showingNewProfileSheet: Bool = false
    @State private var newProfileName: String = ""
    @State private var newProfileDescription: String = ""
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header & Actions
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Controller Profiles")
                            .font(.title3.weight(.bold))
                        Text("Save and switch complete controller setups instantly.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        newProfileName = "Custom Profile \(profileStorage.profiles.count + 1)"
                        newProfileDescription = "Custom settings configuration"
                        showingNewProfileSheet = true
                    }) {
                        Label("New Profile", systemImage: "plus")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                }
                .padding(.horizontal, 4)
                
                // Profiles Grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(profileStorage.profiles) { profile in
                        let isActive = profileStorage.activeProfileId == profile.id
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: profile.iconName)
                                    .font(.title2)
                                    .foregroundColor(isActive ? .accentColor : .secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(6)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.headline.weight(.bold))
                                        .foregroundColor(.primary)
                                    
                                    if isActive {
                                        Text("ACTIVE")
                                            .font(.caption2.monospaced().weight(.bold))
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                Spacer(minLength: 0)
                                
                                Menu {
                                    Button("Duplicate") {
                                        profileStorage.duplicateProfile(profile)
                                    }
                                    Button("Save Current Settings Here") {
                                        var updated = profile
                                        updated.lightbar = manager.lightbarConfig
                                        updated.musicSync = manager.musicSyncConfig
                                        updated.leftTrigger = manager.leftTriggerConfig
                                        updated.rightTrigger = manager.rightTriggerConfig
                                        updated.triggersLinked = manager.triggersLinked
                                        updated.leftRumble = manager.leftRumbleIntensity
                                        updated.rightRumble = manager.rightRumbleIntensity
                                        profileStorage.updateProfile(updated)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        profileStorage.deleteProfile(id: profile.id)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(.secondary)
                                }
                                .menuStyle(BorderlessButtonMenuStyle())
                                .frame(width: 20)
                            }
                            
                            Text(profile.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .frame(height: 28, alignment: .topLeading)
                            
                            // Configuration Badges
                            HStack(spacing: 6) {
                                Text("LED: \(profile.lightbar.mode.rawValue)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                                
                                Text("R2: \(profile.rightTrigger.mode.rawValue)")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12))
                                    .cornerRadius(4)
                            }
                            .foregroundColor(.secondary)
                            
                            // Apply Button
                            Button(action: {
                                profileStorage.activeProfileId = profile.id
                                manager.applyProfile(profile)
                            }) {
                                HStack {
                                    Spacer()
                                    Text(isActive ? "Currently Active" : "Activate Profile")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .background(isActive ? Color.green.opacity(0.15) : Color.accentColor.opacity(0.12))
                                .foregroundColor(isActive ? .green : .accentColor)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isActive ? 1.5 : 1)
                        )
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showingNewProfileSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create New Profile")
                    .font(.title3.weight(.bold))
                
                TextField("Profile Name", text: $newProfileName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                TextField("Description", text: $newProfileDescription)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                HStack {
                    Button("Cancel") {
                        showingNewProfileSheet = false
                    }
                    Spacer()
                    Button("Save from Current Controller Settings") {
                        let newProfile = ControllerProfile(
                            name: newProfileName,
                            description: newProfileDescription,
                            lightbar: manager.lightbarConfig,
                            musicSync: manager.musicSyncConfig,
                            leftTrigger: manager.leftTriggerConfig,
                            rightTrigger: manager.rightTriggerConfig,
                            triggersLinked: manager.triggersLinked,
                            leftRumble: manager.leftRumbleIntensity,
                            rightRumble: manager.rightRumbleIntensity
                        )
                        profileStorage.addProfile(newProfile)
                        profileStorage.activeProfileId = newProfile.id
                        showingNewProfileSheet = false
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                }
                .padding(.top, 8)
            }
            .padding(20)
            .frame(width: 380)
        }
    }
}
