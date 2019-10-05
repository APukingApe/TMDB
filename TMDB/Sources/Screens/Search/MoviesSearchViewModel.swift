//
//  MoviesSearchViewModel.swift
//  TMDB
//
//  Created by Maksym Shcheglov on 02/10/2019.
//  Copyright © 2019 Maksym Shcheglov. All rights reserved.
//

import UIKit
import Combine

final class MoviesSearchViewModel: MoviesSearchViewModelType {

    private weak var navigator: MoviesSearchNavigator?
    private let useCase: MoviesUseCaseType
    private var cancellables: [AnyCancellable] = []

    init(useCase: MoviesUseCaseType, navigator: MoviesSearchNavigator) {
        self.useCase = useCase
        self.navigator = navigator
    }

    func transform(input: MoviesSearchViewModelInput) -> MoviesSearchViewModelOuput {
        let searchInput = input.search.debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        let trigger = searchInput.filter({ !$0.isEmpty })
        let searchResult = trigger
            .flatMapLatest({[unowned self] query in self.useCase.searchMovies(with: query) })
            .share()
            .eraseToAnyPublisher()
        let movies = searchResult
            .map({ result -> State in
                switch result {
                    case .success([]): return .noResults
                    case .success(let movies): return .success(self.viewModels(from: movies))
                    case .failure(let error): return .failure(error)
                }
            })
            .eraseToAnyPublisher()
        let loading: MoviesSearchViewModelOuput = trigger.map({_ in .loading }).eraseToAnyPublisher()

        let cancelSearchState = input.cancelSearch.flatMap({ _ -> AnyPublisher<State, Never> in .just(.idle) }).eraseToAnyPublisher()
        let initialState: AnyPublisher<State, Never> = .just(.idle)
        let noInputState: AnyPublisher<State, Never> = searchInput.filter({ $0.isEmpty }).map({ _ in .idle }).eraseToAnyPublisher()
        let idle: MoviesSearchViewModelOuput = Publishers.Merge3(initialState, cancelSearchState, noInputState).eraseToAnyPublisher()

        input.selection
            .sink(receiveValue: { [unowned self] movieId in self.navigator?.showDetails(forMovie: movieId) })
            .store(in: &cancellables)

        return Publishers.Merge3(idle, loading, movies).removeDuplicates().eraseToAnyPublisher()
    }

    private func viewModels(from movies: [Movie]) -> [MovieViewModel] {
        return movies.map({[unowned self] movie in
            return MovieViewModelBuilder.viewModel(from: movie, imageLoader: {[unowned self] movie in self.useCase.loadImage(for: movie) })
        })
    }

}
