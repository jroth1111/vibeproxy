import Foundation

enum ProxyPaths {
    static func rootDirectoryURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".cli-proxy-api", isDirectory: true)
    }

    static func authDirectoryURL(fileManager: FileManager = .default) -> URL {
        rootDirectoryURL(fileManager: fileManager).appendingPathComponent("auth", isDirectory: true)
    }

    static func userConfigURL(fileManager: FileManager = .default) -> URL {
        rootDirectoryURL(fileManager: fileManager).appendingPathComponent("config.yaml")
    }

    static func metaAIHARURL(fileManager: FileManager = .default) -> URL {
        rootDirectoryURL(fileManager: fileManager).appendingPathComponent("meta.ai.har")
    }

    static func ensureAuthDirectoryLayout(fileManager: FileManager = .default) {
        let rootDirectory = rootDirectoryURL(fileManager: fileManager)
        let authDirectory = authDirectoryURL(fileManager: fileManager)

        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: authDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("[ProxyPaths] Failed to create proxy directories: %@", error.localizedDescription)
            return
        }

        guard let rootEntries = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for sourceURL in rootEntries {
            guard sourceURL.pathExtension.lowercased() == "json" else {
                continue
            }
            guard sourceURL.deletingLastPathComponent() == rootDirectory else {
                continue
            }
            guard authFileType(at: sourceURL, fileManager: fileManager) != nil else {
                continue
            }

            let destinationURL = authDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    // The dedicated auth directory is authoritative once a file exists there.
                    // Do not keep re-overwriting it from legacy root-level auth files, because
                    // that turns startup migration into runtime config churn.
                    continue
                }
                let sourceData = try Data(contentsOf: sourceURL)
                try sourceData.write(to: destinationURL, options: .atomic)
            } catch {
                NSLog(
                    "[ProxyPaths] Failed to migrate auth file %@ into %@: %@",
                    sourceURL.lastPathComponent,
                    destinationURL.path,
                    error.localizedDescription
                )
            }
        }
    }

    private static func authFileType(at url: URL, fileManager: FileManager) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }
        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedType.isEmpty ? nil : normalizedType
    }
}
