import Foundation
import Darwin
import Testing
import Swift7zip
@testable import Core

extension AllCoreTests {
    struct MacMetadataOptionsTests {
        // Existing native fixtures, checked through Info-ZIP rather than the filtered reader.
        @Test(arguments: ["archivers/finder_compress.zip", "zip/appledouble.zip"], [false, true])
        func cleanupRemovesPairedMetadataAndMirrorMarkers(_ fixture: String, _ saveAs: Bool) throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let parts = fixture.split(separator: "/")
            let input = Bundle.module.url(forResource: String(parts[0]), withExtension: nil)!
                .appendingPathComponent(String(parts[1]))
            let source = root.appendingPathComponent("source.zip")
            try FileManager.default.copyItem(at: input, to: source)
            let target = saveAs ? root.appendingPathComponent("copy.zip") : source
            let before = try systemZipEntries(input)
            let removed = Set(before.filter {
                $0.hasPrefix("__MACOSX/") || ["payload/Contents/._Resources", "payload/Contents/Resources/._icon.png", "payload/Contents/MacOS/._helper"].contains($0)
            })
            #expect(!removed.isEmpty)
            try SevenZipArchive.writeArchive(source: source, destination: target, items: [],
                options: .init(format: .zip, excludeMacMetadata: true))
            let after = try systemZipEntries(target)
            #expect(!after.contains { removed.contains($0) })
            #expect(after.filter { !$0.hasSuffix("/") }.sorted() == before.filter { !$0.hasSuffix("/") && !removed.contains($0) }.sorted())
            for path in before where !removed.contains(path) && !path.hasSuffix("/") {
                #expect(try rawPayload(target, path) == rawPayload(input, path), "Payload preserved: \(path)")
            }
        }

        @Test(arguments: ["fresh", "save", "saveAs", "rename"], [false, true])
        func explicitSidecarsRequireContentAndAFinalTarget(_ mode: String, _ exclude: Bool) throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = Bundle.module.url(forResource: "zip", withExtension: nil)!
                .appendingPathComponent("appledouble.zip")
            let metadata = try rawPayload(fixture, "__MACOSX/payload/Contents/._Info.plist")
            let diskSidecar = root.appendingPathComponent("disk-sidecar")
            try metadata.write(to: diskSidecar)
            var controls: [String: Data] = [
                "report.txt": Data("report".utf8),
                "Folder/child.txt": Data("child".utf8),
                ".notes": Data("notes".utf8),
                "._report.txt": Data("ordinary sidecar lookalike".utf8),
                ".DS_Store/keep.txt": Data("a directory, not Finder data".utf8),
                "__MACOSX/ordinary.txt": Data("ordinary namespace content".utf8),
                "legit/plain": Data("plain".utf8),
                "__MACOSX/legit/._plain": Data("paired plain lookalike".utf8),
                "__MACOSX/._orphan.bin": metadata,
                "__MACOSX/orphan-dir/keep.txt": Data("mirror-only directory content".utf8),
                "__MACOSX/._orphan-dir": metadata,
                "._orphan.bin": metadata
            ]
            var base: [ArchiveUpdateItem] = controls.sorted { $0.key < $1.key }.map {
                .addData(archivePath: $0.key, data: $0.value)
            }
            base += [.addDirectory(archivePath: ".DS_Store"), .addDirectory(archivePath: "__MACOSX"),
                     .addDirectory(archivePath: "__MACOSX/empty"), .addDirectory(archivePath: "__MACOSX/legit")]
            let paired: [ArchiveUpdateItem] = [
                .addFile(archivePath: "__MACOSX/._report.txt", diskPath: diskSidecar),
                .addData(archivePath: "._Folder", data: metadata)
            ]
            let source = root.appendingPathComponent("source.zip")
            if mode != "fresh" {
                try SevenZipArchive.writeArchive(destination: source, items: base, options: .init(format: .zip))
            }
            var changes = paired
            if mode == "rename" {
                let entry = try #require(SevenZipArchive(url: source).entries.first { $0.path == "report.txt" })
                changes.append(.move(sourceIndex: entry.index, newPath: "renamed.txt"))
                controls["renamed.txt"] = controls.removeValue(forKey: "report.txt")
            }
            let target = mode == "save" || mode == "rename" ? source : root.appendingPathComponent("output.zip")
            try SevenZipArchive.writeArchive(source: mode == "fresh" ? nil : source, destination: target,
                items: (mode == "fresh" ? base : []) + changes,
                options: .init(format: .zip, excludeMacMetadata: exclude))
            let paths = try systemZipEntries(target)
            let retainedSidecars = (exclude ? [] : ["._Folder"])
                + (!exclude || mode == "rename" ? ["__MACOSX/._report.txt"] : [])
            #expect(paths.filter { !$0.hasSuffix("/") }.sorted()
                == (Array(controls.keys) + retainedSidecars).sorted())
            #expect(paths.contains(".DS_Store/"))
            #expect(paths.contains("__MACOSX/empty/"))
            #expect(paths.contains("__MACOSX/legit/"))
            for (path, data) in controls {
                #expect(try rawPayload(target, path) == data, "Payload preserved: \(path)")
            }
            for path in retainedSidecars {
                #expect(try rawPayload(target, path) == metadata)
            }
        }

        @Test(arguments: ["fresh", "save", "saveAs", "move", "moveSaveAs"], [false, true])
        func cleanupPreservesNewlyOrphanedCompanions(_ mode: String, _ disk: Bool) throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = Bundle.module.url(forResource: "zip", withExtension: nil)!
                .appendingPathComponent("appledouble.zip")
            let metadata = try rawPayload(fixture, "__MACOSX/payload/Contents/._Info.plist")
            let first = mode.hasPrefix("move") ? "._old" : "._foo"
            let inputs: [(String, Data)] = [
                ("__MACOSX/._._foo", metadata), (first, metadata),
                ("__MACOSX/._._Folder", metadata), ("._Folder", metadata),
                ("Folder/child", Data("implied child".utf8)),
                ("foo", Data("payload".utf8)), ("legit/plain", Data("plain".utf8)),
                ("__MACOSX/legit/._plain", Data("ordinary lookalike".utf8))
            ]
            var items: [ArchiveUpdateItem] = []
            for (index, input) in inputs.enumerated() {
                let diskInput = root.appendingPathComponent("input-\(index)")
                try input.1.write(to: diskInput)
                items.append(disk ? .addFile(archivePath: input.0, diskPath: diskInput)
                                  : .addData(archivePath: input.0, data: input.1))
            }
            items += [.addDirectory(archivePath: "__MACOSX"),
                      .addDirectory(archivePath: "__MACOSX/legit")]
            let source = root.appendingPathComponent("source.zip")
            var changes: [ArchiveUpdateItem] = []
            if mode != "fresh" {
                try SevenZipArchive.writeArchive(destination: source, items: items, options: .init(format: .zip))
                if mode.hasPrefix("move") {
                    let entry = try #require(SevenZipArchive(url: source).entries.first { $0.path == first })
                    changes = [.move(sourceIndex: entry.index, newPath: "._foo")]
                }
            }
            let target = mode == "save" || mode == "move" ? source : root.appendingPathComponent("output.zip")
            try SevenZipArchive.writeArchive(source: mode == "fresh" ? nil : source, destination: target,
                items: mode == "fresh" ? items : changes,
                options: .init(format: .zip, excludeMacMetadata: true))
            let paths = try systemZipEntries(target)
            #expect(!paths.contains("._foo"))
            #expect(paths.filter { !$0.hasSuffix("/") }.sorted()
                == ["__MACOSX/._._foo", "__MACOSX/._._Folder", "Folder/child", "__MACOSX/legit/._plain", "foo", "legit/plain"].sorted())
            #expect(paths.contains("__MACOSX/"))
            #expect(paths.contains("__MACOSX/legit/"))
            #expect(try rawPayload(target, "__MACOSX/._._foo") == metadata)
            #expect(try rawPayload(target, "__MACOSX/._._Folder") == metadata)
            #expect(try rawPayload(target, "Folder/child") == Data("implied child".utf8))
            #expect(try rawPayload(target, "__MACOSX/legit/._plain") == Data("ordinary lookalike".utf8))
            #expect(try rawPayload(target, "foo") == Data("payload".utf8))
            #expect(try rawPayload(target, "legit/plain") == Data("plain".utf8))
        }

        @Test(arguments: [false, true], [CompressionOptions.Encryption.zipCrypto, .aes256])
        func encryptedImpliedCompanionRequestsItsOwnPassword(_ rename: Bool, _ cipher: CompressionOptions.Encryption) throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let fixture = Bundle.module.url(forResource: "zip", withExtension: nil)!
                .appendingPathComponent("appledouble.zip")
            let metadata = try rawPayload(fixture, "__MACOSX/payload/Contents/._Info.plist")
            let payload = Data("encrypted child".utf8)
            let source = root.appendingPathComponent("source.zip")
            try SevenZipArchive.writeArchive(destination: source, items: [
                .addData(archivePath: "Folder/child.txt", data: payload),
                .addData(archivePath: "._Folder", data: metadata)
            ], options: .init(format: .zip, password: "secret", encryption: cipher))
            let original = try Data(contentsOf: source)
            let target = rename ? source : root.appendingPathComponent("copy.zip")
            let sentinel = Data("existing destination".utf8)
            if !rename { try sentinel.write(to: target) }
            let before = try Data(contentsOf: target)
            let entry = try #require(SevenZipArchive(url: source).entries.first { $0.path == "Folder/child.txt" })
            let changes: [ArchiveUpdateItem] = rename ? [.move(sourceIndex: entry.index, newPath: "Folder/renamed.txt")] : []
            let options = CompressionOptions(format: .zip, excludeMacMetadata: true)
            do {
                try SevenZipArchive.writeArchive(source: source, destination: target, items: changes, options: options)
                Issue.record("Encrypted raw companion must request a password")
            } catch SevenZipError.passwordMissing { }
            #expect(try Data(contentsOf: target) == before)
            do {
                try SevenZipArchive.writeArchive(source: source, destination: target, items: changes,
                    options: options, sourcePassword: "wrong")
                Issue.record("Encrypted raw companion must reject a wrong password")
            } catch SevenZipError.passwordWrong { }
            #expect(try Data(contentsOf: target) == before)
            try SevenZipArchive.writeArchive(source: source, destination: target, items: changes,
                options: options, sourcePassword: "secret")
            #expect(try systemZipEntries(target) == [rename ? "Folder/renamed.txt" : "Folder/child.txt"])
            let output = try SevenZipArchive(url: target, password: "secret")
            let saved = try #require(output.entries.first)
            #expect(saved.isEncrypted)
            #expect(output.method(ofEntryAt: saved.index)?.contains("AES") == (cipher == .aes256))
            let extracted = root.appendingPathComponent("extracted")
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            let files = try output.extract(index: saved.index, to: extracted)
            #expect(try Data(contentsOf: #require(files[saved.index])) == payload)
            if !rename { #expect(try Data(contentsOf: source) == original) }
        }

        @Test func failedSidecarInspectionLeavesTheDestinationUntouched() throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = root.appendingPathComponent("existing.zip")
            let original = Data("existing destination".utf8)
            try original.write(to: destination)
            #expect(throws: (any Error).self) {
                try SevenZipArchive.writeArchive(destination: destination, items: [
                    .addData(archivePath: "report.txt", data: Data("report".utf8)),
                    .addFile(archivePath: "._report.txt", diskPath: root.appendingPathComponent("missing-sidecar"))
                ], options: .init(format: .zip, excludeMacMetadata: true))
            }
            #expect(try Data(contentsOf: destination) == original)
        }

        private func rawPayload(_ zip: URL, _ path: String) throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", zip.path, path]
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            return data
        }

        @Test @MainActor func metadataPreferenceIsOptIn() throws {
            let defaults = isolatedDefaults()
            let input = CompressionOptions(format: .zip)
            #expect(!ArchiveSaveOptions.applyingFilePreferences(to: input, in: defaults).excludeMacMetadata)
            defaults.set(true, forKey: Keys.excludeMacMetadata)
            #expect(ArchiveSaveOptions.applyingFilePreferences(to: input, in: defaults).excludeMacMetadata)
            defaults.set(false, forKey: Keys.excludeMacMetadata)
            #expect(!ArchiveSaveOptions.applyingFilePreferences(to: input, in: defaults).excludeMacMetadata)
        }

        @Test(arguments: [false, true]) func compressionHonorsMetadataChoice(_ exclude: Bool) async throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let input = root.appendingPathComponent("text.txt")
            try Data("contents".utf8).write(to: input)
            setExtendedAttribute("com.apple.metadata:_kMDItemUserTags", Data("tag".utf8), at: input)
            setExtendedAttribute("com.apple.ResourceFork", Data("resource".utf8), at: input)
            #expect(chflags(input.path, UInt32(UF_HIDDEN)) == 0)
            let archive = root.appendingPathComponent("out.zip")
            try SevenZipArchive.writeArchive(source: nil, destination: archive, items: [
                .addFile(archivePath: "text.txt", diskPath: input),
                .addData(archivePath: ".DS_Store", data: Data("finder".utf8)),
                .addData(archivePath: "._ordinary.txt", data: Data("user data".utf8))
            ], options: .init(format: .zip, excludeMacMetadata: exclude))
            let out = root.appendingPathComponent("out")
            try await extractWithOurEngine(archive, to: out)
            #expect(try Data(contentsOf: out.appendingPathComponent("text.txt")) == Data("contents".utf8))
            #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent(".DS_Store").path) == !exclude)
            #expect(extendedAttribute("com.apple.metadata:_kMDItemUserTags", at: out.appendingPathComponent("text.txt")) == (exclude ? nil : Data("tag".utf8)))
            #expect(extendedAttribute("com.apple.ResourceFork", at: out.appendingPathComponent("text.txt")) == (exclude ? nil : Data("resource".utf8)))
            #expect(try out.appendingPathComponent("text.txt").resourceValues(forKeys: [.isHiddenKey]).isHidden == !exclude)
            #expect(try Data(contentsOf: out.appendingPathComponent("._ordinary.txt")) == Data("user data".utf8))
        }

        @Test(arguments: [CompressionOptions.Format.zip, .sevenZ]) func cleanupKeepsExistingArchivesEncrypted(_ format: CompressionOptions.Format) async throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let file = root.appendingPathComponent("text.txt")
            try Data("private".utf8).write(to: file)
            setExtendedAttribute("com.apple.metadata:_kMDItemUserTags", Data("tag".utf8), at: file)
            let archive = root.appendingPathComponent("locked." + format.rawValue)
            try SevenZipArchive.writeArchive(source: nil, destination: archive, items: [.addFile(archivePath: "text.txt", diskPath: file)], options: .init(format: format, password: "secret", encryptFileNames: format == .sevenZ))
            let original = try Data(contentsOf: archive)
            do {
                try SevenZipArchive.writeArchive(source: archive, destination: archive, items: [],
                    options: .init(format: format, excludeMacMetadata: true))
                Issue.record("Encrypted metadata cleanup must request its password")
            } catch SevenZipError.passwordMissing { }
            #expect(try Data(contentsOf: archive) == original)
            try SevenZipArchive.writeArchive(source: archive, destination: archive, items: [], options: .init(format: format, excludeMacMetadata: true), sourcePassword: "secret")
            let opened = try SevenZipArchive(url: archive, password: "secret")
            #expect(try opened.entries.allSatisfy(\.isEncrypted))
            if format == .sevenZ { #expect(throws: (any Error).self) { try SevenZipArchive(url: archive) } }
            let out = root.appendingPathComponent("out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try opened.extractAll(to: out)
            #expect(try Data(contentsOf: out.appendingPathComponent("text.txt")) == Data("private".utf8))
            #expect(extendedAttribute("com.apple.metadata:_kMDItemUserTags", at: out.appendingPathComponent("text.txt")) == nil)
        }

        @Test(arguments: [false, true]) func customFolderIconsFollowTheOption(_ exclude: Bool) async throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let folder = root.appendingPathComponent("CustomFolder")
            try makeFolderWithCustomIcon(at: folder, fork: Data("icon".utf8))
            let archive = root.appendingPathComponent("folder.zip")
            try SevenZipArchive.writeArchive(source: nil, destination: archive, items: [
                .addDirectory(archivePath: "CustomFolder", diskPath: folder),
                .addFile(archivePath: "CustomFolder/" + customIconFileName, diskPath: folder.appendingPathComponent(customIconFileName))
            ], options: .init(format: .zip, excludeMacMetadata: exclude))
            let out = root.appendingPathComponent("out")
            try await extractWithOurEngine(archive, to: out)
            #expect(finderFlags(at: out.appendingPathComponent("CustomFolder")) == (exclude ? nil : FinderFlag.hasCustomIcon))
            #expect(extendedAttribute("com.apple.ResourceFork", at: out.appendingPathComponent("CustomFolder/" + customIconFileName)) == (exclude ? nil : Data("icon".utf8)))
        }

        @Test(arguments: [false, true]) func existingMetadataIsRemovedWhenRequested(_ saveAs: Bool) async throws {
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            let input = root.appendingPathComponent("text.txt")
            try Data("contents".utf8).write(to: input)
            setExtendedAttribute("com.apple.metadata:_kMDItemUserTags", Data("tag".utf8), at: input)
            let source = root.appendingPathComponent("source.zip")
            try SevenZipArchive.writeArchive(source: nil, destination: source, items: [
                .addFile(archivePath: "text.txt", diskPath: input),
                .addData(archivePath: ".DS_Store", data: Data("finder".utf8)),
                .addData(archivePath: "notes", data: Data("notes".utf8)),
                .addData(archivePath: "._notes", data: Data("ordinary".utf8))
            ], options: .init(format: .zip))
            let target = saveAs ? root.appendingPathComponent("copy.zip") : source
            try SevenZipArchive.writeArchive(source: source, destination: target, items: [], options: .init(format: .zip, excludeMacMetadata: true))
            let out = root.appendingPathComponent("out")
            try await extractWithOurEngine(target, to: out)
            #expect(extendedAttribute("com.apple.metadata:_kMDItemUserTags", at: out.appendingPathComponent("text.txt")) == nil)
            #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent(".DS_Store").path))
            #expect(try Data(contentsOf: out.appendingPathComponent("._notes")) == Data("ordinary".utf8))
        }
    }
}
