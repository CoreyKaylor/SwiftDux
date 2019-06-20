import Foundation
import Combine

/// The primary container of an application's state.
///
/// The store both contains and mutates the state through a provided reducer as it's sent actions.
/// Use the didChange publisher to be notified of changes.
public final class Store<State> where State : StateType {

  /// The current state of the store. Use actions to mutate it.
  public private(set) var state: State
  private let runReducer: (State, Action) -> State

  private let didChangeSubject = PassthroughSubject<Void, Never>()

  /// Subscribe to this publisher to be notified of state changes caused by a particular action.
  public let didChange: AnyPublisher<Void, Never>

  /// Creates a new store for the given state and reducer
  ///
  /// - Parameters
  ///   - state: The initial state of the store. A typically use case is to restore a previous application session with a persisted state object.
  ///   - reducer: A reducer that will mutate the store's state as actions are dispatched to it.
  public init<R>(state: State, reducer: R) where R : Reducer, R.State == State {
    self.state = state
    self.runReducer = reducer.reduceAny
    self.didChange = didChangeSubject.debounce(for: .milliseconds(16), scheduler: RunLoop.main).eraseToAnyPublisher()
  }

}

extension Store : ActionDispatcher, Subscriber {

  /// Sends an action to the store to mutate its state.
  /// - Parameter action: The  action to mutate the state.
  @discardableResult
  public func send(_ action: Action) -> AnyPublisher<Void, Never> {
    if let action = action as? ActionPlan<State> {
      return self.send(actionPlan: action)
    } else if let action = action as? PublishableActionPlan<State> {
      return self.send(actionPlan: action)
    }
    self.state = runReducer(self.state, action)
    self.didChangeSubject.send()
    return Publishers.Just(()).eraseToAnyPublisher()
  }

  /// Handles the sending of normal action plans.
  @discardableResult
  private func send(actionPlan: ActionPlan<State>) -> AnyPublisher<Void, Never> {
    let dispatch: Dispatch = { [unowned self] in self.send($0) }
    let getState: GetState = { [unowned self] in self.state }
    actionPlan.body(dispatch, getState)
    return Publishers.Just(()).eraseToAnyPublisher()
  }

  /// Handles the sending of publishable action plans.
  @discardableResult
  public func send(actionPlan: PublishableActionPlan<State>) -> AnyPublisher<Void, Never> {
    let dispatch: Dispatch = { [unowned self] in self.send($0) }
    let getState: GetState = { [unowned self] in self.state }
    let publisher  = actionPlan.body(dispatch, getState).share()
    publisher.compactMap { $0 }.subscribe(self)
    return publisher.map { _ in () }.eraseToAnyPublisher()
  }

  /// Create a new `StoreActionDispatcher<_>` that acts as a proxy between the action sender and the store. It optionally allows actions to be
  /// modified or monitored.
  /// - Parameter modifyAction: A closure to modify the action before it continues up stream.
  public func dispatcher(modifyAction: StoreActionDispatcher<State>.ActionModifier? = nil) -> StoreActionDispatcher<State> {
    return StoreActionDispatcher(
      upstream: self,
      modifyAction: modifyAction
    )
  }

}
