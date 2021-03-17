import Foundation

public enum TokenizationError: Error, Equatable {
    case contentError(error: ContentError)
    case emptyReport
    case transformationError
}

public enum ContentError: Error, Equatable {
    case emptyFilename
    case fileNotFound(name: String)
    case noFileAccess(path: String)
    case emptyContent
    case failedToLoadContent
    case fileImportFailed(error: Error)

    public static func == (lhs: ContentError, rhs: ContentError) -> Bool {
        switch (lhs, rhs) {
            case (.emptyFilename, .emptyFilename),
                 (.emptyContent, .emptyContent),
                 (.failedToLoadContent, .failedToLoadContent):
                return true
            case let (.fileNotFound(lhsFile), .fileNotFound(rhsFile)):
                return lhsFile == rhsFile
            case let (.noFileAccess(lhsFile), .noFileAccess(rhsFile)):
                return lhsFile == rhsFile
            case let (.fileImportFailed(lhsError), .fileImportFailed(rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
        }
    }
}
