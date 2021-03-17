import Foundation

extension URL {
    public static let emptyFilename = URL(fileURLWithPath: "")
    public static let emptyContent = URL(fileURLWithPath: "/")    
    public static let basic = URL(fileURLWithPath: "basic")

}

public extension Content {
    static var empty = ""
    static var basic = "basic"
}

public struct TokenizedReport: Equatable {
    public var content: Content
    
    public init(content: Content) {
        self.content = content
    }
    
    public static let empty = TokenizedReport(content: Content.empty)
    public static let basic = TokenizedReport(content: Content.basic)
}

public struct Report {
    public var tokenizedReport: TokenizedReport

    public init(tokenizedReport: TokenizedReport) {
        self.tokenizedReport = tokenizedReport
    }

    public static let empty = Report(tokenizedReport: TokenizedReport.empty)
    public static let basic = Report(tokenizedReport: TokenizedReport.basic)
}

