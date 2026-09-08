import SwiftUI
import UniformTypeIdentifiers

/// A minimal `FileDocument` wrapping already-encoded conversation
/// export JSON, so `.fileExporter` can write it to a user-chosen
/// location.
///
/// Deliberately holds pre-encoded `Data` rather than a `Conversation`/
/// `[TranscriptMessage]` pair — the actual encoding (and its
/// versioning contract) lives entirely in `ConversationExportCoding`,
/// which is unit-tested on its own; this type has no logic of its own
/// to test.
struct ConversationExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
