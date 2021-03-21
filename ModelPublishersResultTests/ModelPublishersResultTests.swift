//
//  ModelPublishersResultTests.swift
//
//
//  Created by Igor Malyarov on 19.03.2021.
//
// This example (with tests) illustrate how to use flatMap inside the pipeline
// if working with publishers that return Result type.
//
// Note: Instead of Failure == Never one could use some ServiceError: Error,
// that is separated from DomainError, for example, some NetworkingError.
// In that case use catch, tryCatch with tryMap or tryMap with mapError operators to replace the error conditions. See:
// https://heckj.github.io/swiftui-notes/#patterns-continual-error-handling
// https://heckj.github.io/swiftui-notes/#patterns-constrained-network
// https://heckj.github.io/swiftui-notes/#normalizing-errors-from-a-datataskpublisher
//

import Foundation
import XCTest
import Combine

typealias Content = String

struct Report: Equatable {
    var content: Content
}
struct Project: Equatable {
    var report: Report
}

enum DomainError: Error, Equatable, CustomStringConvertible {

    case unknown, emptyContent

    /// https://developer.apple.com/documentation/swift/customstringconvertible
    /// Types that conform to the `CustomStringConvertible` protocol can provide their own representation to be used when converting an instance to a string. The `String(describing:)` initializer is the preferred way to convert an instance of any type to a string. If the passed instance conforms to CustomStringConvertible, the String(describing:) initializer and the print(_:) function use the instance’s custom description property.
    /// Accessing a type’s description property directly or using CustomStringConvertible as a generic constraint is discouraged.
    var description: String {
        switch self {
            case .unknown:      return "An unknown error occurred"
            case .emptyContent: return "Empty Content"
        }
    }
}

#warning("write tests for ContentError, esp. func '==' (Equatable)")
enum ContentError: Error, Equatable {
    case fileImportFailed(Error), unknown

    public static func == (lhs: ContentError, rhs: ContentError) -> Bool {
        switch (lhs, rhs) {
            case (.unknown, .unknown):
                return true
            case let (.fileImportFailed(lhsError), .fileImportFailed(rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
        }
    }
}

typealias URLResult = Result<URL, ContentError>
typealias ContentResult = Result<Content, DomainError>
typealias ReportResult = Result<Report, DomainError>
typealias ProjectResult = Result<Project, DomainError>

extension URL {
    static let empty = URL(fileURLWithPath: "")
}

class ModelPublishersResultTests: XCTestCase {
    var testModel: TestModel!

    enum Factory {
        static func contentOf(_ urlResult: URLResult) -> AnyPublisher<ContentResult, Never> {
            let contentResult: ContentResult = urlResult
                .map(\.lastPathComponent)
                .mapError { _ in DomainError.unknown }
            return Just(contentResult).eraseToAnyPublisher()
        }
        static func reporter(_ contentResult: ContentResult) -> AnyPublisher<ReportResult, Never> {
            let reportResult: ReportResult = contentResult.map(Report.init)
            return Just(reportResult).eraseToAnyPublisher()
        }
        static func projector(_ reportResult: ReportResult) -> AnyPublisher<ProjectResult, Never> {
            let projectResult: ProjectResult = reportResult.map(Project.init)
            return Just(projectResult).eraseToAnyPublisher()
        }
    }

    class TestModel: ObservableObject {
        #warning("need to make 'private' but have to test...")
        let urlSubject = PassthroughSubject<URLResult, Never>()

        @Published private(set) var reportResult: ReportResult
        @Published private(set) var projectResult: ProjectResult

        private let reporter: (ContentResult) -> AnyPublisher<ReportResult, Never>
        private let projector: (ReportResult) -> AnyPublisher<ProjectResult, Never>

        init(contentOf: @escaping (URLResult) -> AnyPublisher<ContentResult, Never>,
             reporter: @escaping (ContentResult) -> AnyPublisher<ReportResult, Never>,
             projector: @escaping (ReportResult) -> AnyPublisher<ProjectResult, Never>
        ) {
            reportResult = .failure(.unknown)
            projectResult = .failure(.unknown)

            self.reporter = reporter
            self.projector = projector

            // create publishers (constants) to assure pipeline(s) returns correct type
            //
            // switchToLatest va flatMap see
            // https://heckj.github.io/swiftui-notes/#reference-switchtolatest
            // switchToLatest operates similarly to flatMap, taking in a publisher instance and returning its value (or values). Where flatMap operates over the values it is provided, switchToLatest operates on whatever publisher it is provided. The primary difference is in where it gets the publisher. In flatMap, the publisher is returned within the closure provided to flatMap, and the operator works upon that to subscribe and provide the relevant value down the pipeline. In switchToLatest, the publisher instance is provided as the output type from a previous publisher or operator.
            // The most common form of using this is with a one-shot publisher such as Just getting its value as a result of a map transform.
            // It is also commonly used when working with an API that provides a publisher. switchToLatest assists in taking the result of the publisher and sending that down the pipeline rather than sending the publisher as the output type.
            //
            // for chaining map() and switchToLatest() see example in
            // https://www.raywenderlich.com/books/combine-asynchronous-programming-with-swift/v1.0/chapters/5-combining-operators#toc-chapter-008-anchor-004
            // consider the following scenario: Your user taps a button that triggers a network request. Immediately afterward, the user taps the button again, which triggers a second network request. But how do you get rid of the pending request, and only use the latest request?
            //
            // assign(to:)
            // https://developer.apple.com/documentation/combine/publishers/share/assign(to:)
            // Use this operator when you want to receive elements from a publisher and republish them through a property marked with the @Published attribute. The assign(to:) operator manages the life cycle of the subscription, canceling the subscription automatically when the Published instance deinitializes.
            //
            let pub0: AnyPublisher<ContentResult, Never> =
            urlSubject
                .receive(on: DispatchQueue.global())
                .map(contentOf)
                .switchToLatest()
                .eraseToAnyPublisher()

            pub0
                .flatMap(reporter)
                .receive(on: DispatchQueue.main)
                .assign(to: &$reportResult)
            /*
            let pub1: AnyPublisher<ReportResult, Never> =
                urlSubject
                .receive(on: DispatchQueue.global())
                //.flatMap { urlResult in contentOf(urlResult) }
                .flatMap(contentOf)
                // .flatMap { contentResult in self.reporter(contentResult) }
                .flatMap(reporter)
                .eraseToAnyPublisher()

            pub1.receive(on: DispatchQueue.main)
                .assign(to: &$reportResult)
             */
            let pub2: AnyPublisher<ProjectResult, Never> =
                $reportResult
                .flatMap(projector)
                .eraseToAnyPublisher()

            pub2.receive(on: DispatchQueue.main)
                .assign(to: &$projectResult)

        }

        // MARK: Intensions

        func handleFileImporter(_ result: Result<URL, Error>) {
            let urlResult = result//.mapError(ContentError.fileImportFailed)
                .mapError { error -> ContentError in
                    error as? ContentError ?? .fileImportFailed(error)
                }
            urlSubject.send(urlResult)
        }

        #warning("uncomment in project")
        //        func setFilename(to filename: String) {
        //            urlResult = ContentLoader.urlOfResourceFile(named: filename)
        //        }

    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        testModel = TestModel(contentOf: Factory.contentOf,
                              reporter: Factory.reporter,
                              projector: Factory.projector)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_handleFileImporter() {
        let expectation = expectation(description: String(describing: #function))
        var results = [URLResult]()
        let cancellable = testModel.urlSubject.sink { results.append($0) }

        let delayInterval: TimeInterval = 0.5
        let urlResults: [Result<URL, Error>] = [
            .failure(DomainError.unknown),
            .success(URL(fileURLWithPath: "bingo")),
            .failure(DomainError.emptyContent),
            .success(URL(fileURLWithPath: "bingo-bingo")),
            .failure(ContentError.unknown),
        ]

        for element in urlResults.enumerated() {
            let delay = delayInterval * Double(element.offset + 2)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.testModel.handleFileImporter(element.element)
            }
        }

        let interval = 1 + Double(urlResults.count) * delayInterval
        // @Published never completes, so I'm using time interval to finish test
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: expectation.fulfill)

        waitForExpectations(timeout: interval + 2)
        XCTAssertNotNil(cancellable)
        let expectedValues: [URLResult] = [
            .failure(ContentError.fileImportFailed(DomainError.unknown)),
            .success(URL(fileURLWithPath: "bingo")),
            .failure(ContentError.fileImportFailed(DomainError.emptyContent)),
            .success(URL(fileURLWithPath: "bingo-bingo")),
            .failure(ContentError.unknown),
        ]
        XCTAssertEqual(expectedValues, results)
    }

    func test_handleFileImporter_projectResult() {
        let expectation = expectation(description: String(describing: #function))
        var results = [ProjectResult]()
        let cancellable = testModel.$projectResult.sink { results.append($0) }

        let delayInterval: TimeInterval = 0.5
        let urlResults: [Result<URL, Error>] = [
            .success(URL(fileURLWithPath: "bingo")),
            .failure(DomainError.unknown),
            .success(URL(fileURLWithPath: "bingo-bingo")),
            .failure(DomainError.unknown),
            .success(URL(fileURLWithPath: "bingo-bingo-bingo")),
        ]

        for element in urlResults.enumerated() {
            let delay = delayInterval * Double(element.offset + 2)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.testModel.handleFileImporter(element.element)
            }
        }

        let interval = 1 + Double(urlResults.count) * delayInterval
        // @Published never completes, so I'm using time interval to finish test
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: expectation.fulfill)

        waitForExpectations(timeout: interval + 2)
        XCTAssertNotNil(cancellable)
        let expectedValues: [ProjectResult] = [
            .failure(.unknown),
            .failure(.unknown),
            .success(Project(report: Report(content: "bingo"))),
            .failure(.unknown),
            .success(Project(report: Report(content: "bingo-bingo"))),
            .failure(.unknown),
            .success(Project(report: Report(content: "bingo-bingo-bingo"))),
        ]
        XCTAssertEqual(expectedValues, results)
    }

}
