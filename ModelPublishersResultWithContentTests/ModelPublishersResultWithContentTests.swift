//
//  ModelPublishersResultTests.swift
//
//
//  Created by Igor Malyarov on 20.03.2021.
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

enum DomainError: Error, Equatable { case error }
enum ContentError: Error { case fileImportFailed(Error) }

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
                .mapError { _ in DomainError.error }
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
        let urlSubject = PassthroughSubject<URLResult, Never>()

        @Published private(set) var contentResult: ContentResult
        @Published private(set) var reportResult: ReportResult
        @Published private(set) var projectResult: ProjectResult

        private let reporter: (ContentResult) -> AnyPublisher<ReportResult, Never>
        private let projector: (ReportResult) -> AnyPublisher<ProjectResult, Never>

        init(contentOf: @escaping (URLResult) -> AnyPublisher<ContentResult, Never>,
             reporter: @escaping (ContentResult) -> AnyPublisher<ReportResult, Never>,
             projector: @escaping (ReportResult) -> AnyPublisher<ProjectResult, Never>
        ) {
            contentResult = .failure(.error)
            reportResult = .failure(.error)
            projectResult = .failure(.error)

            self.reporter = reporter
            self.projector = projector

            // create publishers (constants) to assure pipeline returns correct type

            let pub0: AnyPublisher<ReportResult, Never> =
                $contentResult
                .receive(on: DispatchQueue.global())
                // .flatMap { contentResult in self.reporter(contentResult) }
                .flatMap(reporter)
                .eraseToAnyPublisher()

            pub0.receive(on: DispatchQueue.main)
                /// https://developer.apple.com/documentation/combine/publishers/share/assign(to:)
                .assign(to: &$reportResult)

            let pub1: AnyPublisher<ReportResult, Never> =
                urlSubject
                .receive(on: DispatchQueue.global())
                //.flatMap { urlResult in contentOf(urlResult) }
                .flatMap(contentOf)
                // .flatMap { contentResult in self.reporter(contentResult) }
                .flatMap(reporter)
                .eraseToAnyPublisher()

            pub1.receive(on: DispatchQueue.main)
                /// https://developer.apple.com/documentation/combine/publishers/share/assign(to:)
                .assign(to: &$reportResult)

            let pub2: AnyPublisher<ProjectResult, Never> =
                $reportResult
                .flatMap(projector)
                .eraseToAnyPublisher()

            pub2.receive(on: DispatchQueue.main)
                /// https://developer.apple.com/documentation/combine/publishers/share/assign(to:)
                .assign(to: &$projectResult)

            //            $reportResult
            //                .sink { print("$reportResult: \($0)") }
            //                .store(in: &cancellables)
            //            $projectResult
            //                .sink { print("$projectResult: \($0)") }
            //                .store(in: &cancellables)
        }

        //        private var cancellables = Set<AnyCancellable>()

        //        deinit {
        //            for cancell in cancellables {
        //                cancell.cancel()
        //            }
        //        }

        func setContentResult(to contentResult: ContentResult) {
            self.contentResult = contentResult
        }
        // MARK: - Intensions

        func handleFileImporter(_ result: Result<URL, Error>) {
            let urlResult = result.mapError(ContentError.fileImportFailed)
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

    func test_handleFileImporter_projectResult() {
        let expectation = expectation(description: String(describing: #function))
        var results = [ProjectResult]()
        let cancellable = testModel.$projectResult.sink { results.append($0) }

        let delayInterval: TimeInterval = 0.5
        let urlResults: [Result<URL, Error>] = [
            .success(URL(fileURLWithPath: "bingo")),
            .failure(DomainError.error),
            .success(URL(fileURLWithPath: "bingo-bingo")),
            .failure(DomainError.error),
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
            .failure(.error),
            .failure(.error),
            .failure(.error),
            .success(Project(report: Report(content: "bingo"))),
            .failure(.error),
            .success(Project(report: Report(content: "bingo-bingo"))),
            .failure(.error),
            .success(Project(report: Report(content: "bingo-bingo-bingo"))),
        ]
        XCTAssertEqual(expectedValues, results)
    }

    func test_setContentResult() throws {
        let expectation = expectation(description: String(describing: #function))
        var results = [ProjectResult]()
        let cancellable = testModel.$projectResult.sink { results.append($0) }

        let delayInterval: TimeInterval = 0.4
        let contentResults: [ContentResult] = [
            .success("bingo"),
            .failure(.error),
            .success("bingo-bingo"),
            .failure(.error),
            .success("bingo-bingo-bingo"),
        ]

        for element in contentResults.enumerated() {
            let delay = delayInterval * Double(element.offset + 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.testModel.setContentResult(to: element.element)
            }
        }

        let interval = 1 + Double(contentResults.count) * delayInterval
        // @Published never completes, so I'm using time interval to finish test
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: expectation.fulfill)

        waitForExpectations(timeout: interval + 2)
        XCTAssertNotNil(cancellable)
        let expectedValues: [ProjectResult] = [
            .failure(.error),
            .failure(.error),
            .failure(.error),
            .success(Project(report: Report(content: "bingo"))),
            .failure(.error),
            .success(Project(report: Report(content: "bingo-bingo"))),
            .failure(.error),
            .success(Project(report: Report(content: "bingo-bingo-bingo"))),
        ]
        XCTAssertEqual(expectedValues, results)
    }

}
