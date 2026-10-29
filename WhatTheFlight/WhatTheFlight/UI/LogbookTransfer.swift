//
//  LogbookTransfer.swift
//  WhatTheFlight
//
//  Settings → Logbook → Export & Backup (iPhone / iPad): the logbook as a CSV for a
//  spreadsheet, a backup folder (Logbook.json plus photos) saved to Files, and restoring
//  one. The formats are in `Radar/LogbookExport.swift`.
//

#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// What Export & Backup writes: the CSV, or a backup folder with Logbook.json and a Photos
/// folder of the logbook's photo copies. One document type, so one exporter serves both.
struct LogbookExportDocument: FileDocument {
    enum Content {
        case csv(String)
        /// Photo id → its file in the logbook's photo store.
        case backup(json: Data, photos: [String: URL])
    }

    static var readableContentTypes: [UTType] { [.commaSeparatedText, .folder] }

    let content: Content

    init(_ content: Content) { self.content = content }

    init(configuration: ReadConfiguration) throws {
        content = .csv(String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self))
    }

    var contentType: UTType {
        if case .csv = content { return .commaSeparatedText }
        return .folder
    }

    var filename: String {
        if case .csv = content { return LogbookExport.suggestedName() }
        return LogbookExport.suggestedName("Backup")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        switch content {
        case .csv(let text):
            return FileWrapper(regularFileWithContents: Data(text.utf8))
        case .backup(let json, let photos):
            var photoFiles: [String: FileWrapper] = [:]
            for (id, url) in photos {
                guard let wrapper = try? FileWrapper(url: url, options: .immediate) else { continue }
                wrapper.preferredFilename = "\(id).heic"
                photoFiles["\(id).heic"] = wrapper
            }
            let file = FileWrapper(regularFileWithContents: json)
            file.preferredFilename = LogbookExport.backupFileName
            var children = [LogbookExport.backupFileName: file]
            if !photoFiles.isEmpty {
                let folder = FileWrapper(directoryWithFileWrappers: photoFiles)
                folder.preferredFilename = LogbookExport.photoFolderName
                children[LogbookExport.photoFolderName] = folder
            }
            return FileWrapper(directoryWithFileWrappers: children)
        }
    }
}

/// The section on the Logbook settings page.
struct LogbookTransferSection: View {
    let logbook: Logbook

    @State private var export: LogbookExportDocument?
    @State private var isExporting = false
    @State private var isRestoring = false
    @State private var message: (title: String, text: String)?

    var body: some View {
        Section {
            Button("Export as Spreadsheet", systemImage: "tablecells") {
                export = LogbookExportDocument(.csv(LogbookExport.csv(logbook.sightings)))
                isExporting = true
            }
            .disabled(logbook.isEmpty)
            Button("Back Up Logbook…", systemImage: "externaldrive.badge.plus") {
                makeBackup()
            }
            .disabled(logbook.isEmpty)
            Button("Restore from Backup…", systemImage: "arrow.counterclockwise.circle") {
                isRestoring = true
            }
            // Its own view: an importer and an exporter on the same one can clash.
            .fileImporter(isPresented: $isRestoring, allowedContentTypes: [.folder, .json]) { result in
                switch result {
                case .success(let url): restore(from: url)
                case .failure(let error): message = ("Couldn't Restore", error.localizedDescription)
                }
            }
        } header: {
            SettingsHeader("Export & backup", info: "The spreadsheet is a CSV with a row per sighting that opens in Numbers or Excel. A backup is a folder with every sighting and photo, saved wherever you like in Files; restoring one merges it into the logbook, so nothing already here is lost.")
        }
        .fileExporter(isPresented: $isExporting, document: export, contentType: export?.contentType ?? .commaSeparatedText,
                      defaultFilename: export?.filename) { result in
            let isBackup = export?.contentType == .folder
            switch result {
            case .success:
                if isBackup { message = ("Backed Up", "\(RadarFormat.wholeNumber(logbook.sightings.count)) sightings and their photos are saved.") }
            case .failure(let error):
                message = (isBackup ? "Couldn't Back Up" : "Couldn't Export", error.localizedDescription)
            }
        }
        .alert(message?.title ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message?.text ?? "")
        }
    }

    private func makeBackup() {
        do {
            let json = try LogbookExport.backupData(logbook.sightings)
            var photos: [String: URL] = [:]
            for photo in logbook.allPhotos {
                if let url = logbook.photoStore.url(for: photo.id), FileManager.default.fileExists(atPath: url.path) {
                    photos[photo.id] = url
                }
            }
            export = LogbookExportDocument(.backup(json: json, photos: photos))
            isExporting = true
        } catch {
            message = ("Couldn't Back Up", error.localizedDescription)
        }
    }

    /// A backup folder, or just its Logbook.json (or the app's own Logbook.json).
    private func restore(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        let jsonURL = isFolder.boolValue ? url.appendingPathComponent(LogbookExport.backupFileName) : url
        let photoFolder = isFolder.boolValue ? url.appendingPathComponent(LogbookExport.photoFolderName, isDirectory: true) : nil
        do {
            let sightings = try LogbookExport.readBackup(Data(contentsOf: jsonURL))
            let result = logbook.restore(sightings) { id in
                guard let file = photoFolder?.appendingPathComponent("\(id).heic"),
                      FileManager.default.fileExists(atPath: file.path) else { return nil }
                return file
            }
            var parts = ["\(RadarFormat.wholeNumber(result.added)) new sightings"]
            if result.updated > 0 { parts.append("\(RadarFormat.wholeNumber(result.updated)) filled in") }
            if result.photos > 0 { parts.append("\(RadarFormat.wholeNumber(result.photos)) photos") }
            message = ("Restored", parts.joined(separator: ", ") + ".")
        } catch {
            message = ("Couldn't Restore", (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
#endif
