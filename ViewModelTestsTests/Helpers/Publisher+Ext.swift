import Combine

extension Publisher {
    public func convertToResult() -> AnyPublisher<Result<Output, Failure>, Never> {
        #warning("mind assertNoFailure")
        return map(Result.success)
            .catch { error in Just(.failure(error)) }
            .assertNoFailure("Result: ")
            .eraseToAnyPublisher()
    }

}
