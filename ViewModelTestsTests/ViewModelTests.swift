//
//  ViewModelTests.swift
//  ViewModelTests
//
//  Created by Igor Malyarov on 17.03.2021.
//

import XCTest
import Combine

final class ViewModelTests: XCTestCase {
    var viewModel:  ViewModel!

    func contentsOf(_ url: URL) -> AnyPublisher<Content, ContentError> {
        let result: ContentResult = {
            switch url {
                case URL.emptyFilename: return .failure(.emptyFilename)
                case URL.emptyContent:  return .failure(.emptyContent)
                case URL.basic:         return .success(.basic)
                default:                return .success(url.absoluteString)
            }
        }()
        return result.publisher.eraseToAnyPublisher()
    }

    func tokenize(_ content: Content) -> AnyPublisher<TokenizedReport, TokenizationError> {
        let result: TokenizationResult = {
            switch content {
                case .empty: return .failure(.emptyReport)
                case .basic: return .success(.basic)
                default:     return .success(TokenizedReport(content: content))
            }
        }()
        return result.publisher.eraseToAnyPublisher()
    }

    func makeReport(_ tokenizedReport: TokenizedReport) -> AnyPublisher<Report, TokenizationError> {
        let result: ReportResult = {
            switch tokenizedReport {
                case .empty: return .failure(.emptyReport)
                case .basic: return .success(.basic)
                default:     return .success(Report(tokenizedReport: tokenizedReport))
            }
        }()
        return result.publisher.eraseToAnyPublisher()
    }

    class ViewModel: ObservableObject {
        @Published private(set) var tokenizationResult: TokenizationResult
        @Published private(set) var reportResult: ReportResult

        var urlResult: Result<URL, ContentError>

        init(contentsOf: @escaping (URL) -> AnyPublisher<Content, ContentError>,
             tokenize: @escaping (Content) -> AnyPublisher<TokenizedReport, TokenizationError>,
             makeReport: @escaping (TokenizedReport) -> AnyPublisher<Report, TokenizationError>
        ) {
            urlResult = .failure(.emptyContent)
            tokenizationResult = .failure(.emptyReport)
            reportResult = .failure(.emptyReport)

            urlResult.publisher
                .receive(on: DispatchQueue.global())
                .flatMap(contentsOf)
                .mapError(TokenizationError.contentError)
                .flatMap(tokenize)
                .convertToResult()
                .receive(on: DispatchQueue.main)
                /// https://developer.apple.com/documentation/combine/publishers/share/assign(to:)
                .assign(to: &$tokenizationResult)

            tokenizationResult.publisher
                .receive(on: DispatchQueue.global())
                .flatMap(makeReport)
                .convertToResult()
                .receive(on: DispatchQueue.main)
                .assign(to: &$reportResult)
        }

        // MARK: - Intensions

        func handleFileImporter(result: Result<URL, Error>) {
            urlResult = result.mapError(ContentError.fileImportFailed)
        }

        #warning("uncomment in project")
        //        func setFilename(to filename: String) {
        //            urlResult = ContentLoader.urlOfResourceFile(named: filename)
        //        }

    }

    override func setUpWithError() throws {
        viewModel = ViewModel(contentsOf: contentsOf, tokenize: tokenize, makeReport: makeReport)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_emptyFilename() throws {
        let expectation = expectation(description: String(describing: #function))
        var tokenizationResults = [TokenizationResult]()
        let cancellable = viewModel.$tokenizationResult.sink { tokenizationResult in
            tokenizationResults.append(tokenizationResult)
        }

        viewModel.handleFileImporter(result: .success(URL(fileURLWithPath: "")))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: expectation.fulfill)

        waitForExpectations(timeout: 4)
        XCTAssertNotNil(cancellable)
        let expectedResults: [TokenizationResult] = [
            .failure(.emptyReport),
            .failure(.contentError(error: .emptyContent))
        ]
        XCTAssertEqual(expectedResults, tokenizationResults)
    }

    func test_emptyContent() throws {
        let expectation = expectation(description: String(describing: #function))
        var tokenizationResults = [TokenizationResult]()
        let cancellable = viewModel.$tokenizationResult.sink { tokenizationResult in
            tokenizationResults.append(tokenizationResult)
        }

        viewModel.handleFileImporter(result: .success(URL(fileURLWithPath: "/")))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: expectation.fulfill)

        waitForExpectations(timeout: 5)
        XCTAssertNotNil(cancellable)
        let expectedResults: [TokenizationResult] = [
            .failure(TokenizationError.emptyReport),
            .failure(.contentError(error: .emptyContent))
        ]
        XCTAssertEqual(expectedResults, tokenizationResults)
    }

    func test_basic() throws {
        let expectation = expectation(description: String(describing: #function))
        var tokenizationResults = [TokenizationResult]()
        let cancellable = viewModel.$tokenizationResult.sink { tokenizationResult in
            tokenizationResults.append(tokenizationResult)
        }

        viewModel.handleFileImporter(result: .success(URL(fileURLWithPath: "basic")))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: expectation.fulfill)

        waitForExpectations(timeout: 4)
        XCTAssertNotNil(cancellable)
        let expectedResults: [TokenizationResult] = [
            .failure(.emptyReport),
            .failure(.contentError(error: .emptyContent))
        ]
        XCTAssertEqual(expectedResults, tokenizationResults)
    }

    func test_contentsOf() {
        let expectation = expectation(description: String(describing: #function))
        let urls = [URL(fileURLWithPath: "some"),
                    URL.basic,
                    URL.emptyFilename,
                    URL.emptyContent]
        var contents = [ContentResult]()
        let cancellable0: AnyPublisher<Content, ContentError> = urls.publisher
            .flatMap(contentsOf)
            .eraseToAnyPublisher()

        let c0: AnyPublisher<Result<Content, ContentError>, Never> = cancellable0
            .convertToResult()

        let cancellable = urls.publisher
            .flatMap(contentsOf)
            .convertToResult()
            .print()
            .sink { value in
                contents.append(value)
            }

        let cancellable2 = urls.publisher
            .flatMap { url in
                self.contentsOf(url).convertToResult()
            }
            .print("cancellable2: ")
            .sink { value in
                contents.append(value)
            }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: expectation.fulfill)

        waitForExpectations(timeout: 4)
        XCTAssertNotNil(cancellable)
        let expected: [ContentResult] = [
            .success("file:///some"),
            .success(.basic),
            .failure(.emptyFilename),
            .failure(.emptyContent)
        ]
        XCTAssertEqual(contents, expected)
    }

}
