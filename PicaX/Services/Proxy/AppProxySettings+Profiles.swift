import Foundation

extension AppProxySettings {
    @discardableResult
    func importBuiltInProxyYAML(
        _ yaml: String
    ) throws -> AppBuiltInProxyImportSummary {
        try importBuiltInProxyParseResult(
            ClashYAMLProxyParser.parse(yaml)
        )
    }

    @discardableResult
    func importBuiltInProxyParseResult(
        _ parsed: ClashYAMLProxyParser.ParseResult
    ) throws -> AppBuiltInProxyImportSummary {
        guard !parsed.candidates.isEmpty else {
            throw ClashYAMLProxyParser.ParseError.noSupportedNodes(
                parsed.skippedMessages
            )
        }
        let result = try AppBuiltInProxyProfileStore.importCandidates(
            parsed.candidates,
            into: appBuiltInProxyProfiles,
            defaults: defaults,
            storageKey: AppProxySettingsStorage.Key.appBuiltInProxyProfiles
        )
        appBuiltInProxyProfiles = result.profiles
        if selectedBuiltInProxyProfile == nil {
            selectedBuiltInProxyID = result.profiles.first?.id
            persistSelectedBuiltInProxyID()
        }
        appProxyDidChange()
        return AppBuiltInProxyImportSummary(
            importedCount: result.importedCount,
            replacedCount: result.replacedCount,
            skippedMessages: parsed.skippedMessages
        )
    }

    func selectBuiltInProxyProfile(_ id: UUID) throws {
        guard let profile = appBuiltInProxyProfiles.first(where: {
            $0.id == id
        }) else {
            throw AppProxyError.builtInProfileMissing
        }
        _ = try AppBuiltInProxyProfileStore.secret(for: profile)
        let selectionChanged = selectedBuiltInProxyID != id
        selectedBuiltInProxyID = id
        persistSelectedBuiltInProxyID()
        if appNetworkRoutingMode == .builtInProxy {
            if selectionChanged {
                appProxyDidChange()
            }
        } else {
            activateRoutingMode(.builtInProxy)
        }
    }

    func selectNextBuiltInProxyAfterForbidden(
        failedProfileID: UUID,
        excluding excludedProfileIDs: Set<UUID>
    ) -> Bool {
        guard automaticallySelectBuiltInProxy,
              appNetworkRoutingMode == .builtInProxy,
              appBuiltInProxyProfiles.count > 1 else {
            return false
        }

        if let selectedBuiltInProxyID,
           selectedBuiltInProxyID != failedProfileID,
           !excludedProfileIDs.contains(selectedBuiltInProxyID),
           let selectedProfile = selectedBuiltInProxyProfile,
           (try? AppBuiltInProxyProfileStore.secret(
               for: selectedProfile
           )) != nil {
            return true
        }

        let startID = selectedBuiltInProxyID ?? failedProfileID
        let startIndex = appBuiltInProxyProfiles.firstIndex {
            $0.id == startID
        } ?? -1
        for offset in 1...appBuiltInProxyProfiles.count {
            let index = (startIndex + offset)
                % appBuiltInProxyProfiles.count
            let profile = appBuiltInProxyProfiles[index]
            guard !excludedProfileIDs.contains(profile.id),
                  (try? AppBuiltInProxyProfileStore.secret(
                      for: profile
                  )) != nil else {
                continue
            }
            selectedBuiltInProxyID = profile.id
            persistSelectedBuiltInProxyID()
            appProxyDidChange(resetSessions: false)
            return true
        }
        return false
    }

    func removeBuiltInProxyProfiles(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        let profiles = try AppBuiltInProxyProfileStore.remove(
            profileIDs: ids,
            from: appBuiltInProxyProfiles,
            defaults: defaults,
            storageKey: AppProxySettingsStorage.Key.appBuiltInProxyProfiles
        )
        guard profiles.count != appBuiltInProxyProfiles.count else {
            return
        }
        appBuiltInProxyProfiles = profiles
        if selectedBuiltInProxyProfile == nil {
            selectedBuiltInProxyID = profiles.first?.id
            persistSelectedBuiltInProxyID()
        }
        appProxyDidChange()
    }

    func clearBuiltInProxyProfiles() throws {
        try removeBuiltInProxyProfiles(
            Set(appBuiltInProxyProfiles.map(\.id))
        )
    }

    var selectedBuiltInProxyProfile: AppBuiltInProxyProfile? {
        guard let selectedBuiltInProxyID else { return nil }
        return appBuiltInProxyProfiles.first {
            $0.id == selectedBuiltInProxyID
        }
    }
}
