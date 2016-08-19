//
//  Copyright (c) 2016 Anton Mironov
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom
//  the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
//  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

import Foundation

public protocol ExecutionContext : class {
  var executor: Executor { get }
}

public extension Future {
  final func map<U: ExecutionContext, V>(context: U?, _ transform: @escaping (Value, U) throws -> V) -> Future<Failable<V>> {
    let promise = Promise<Failable<V>>()
    weak var weakContext = context
    let handler = FutureHandler<Value>(executor: .immediate) { value in
      if let context = weakContext {
        context.executor.execute {
          promise.complete(with: failable { try transform(value, context) })
        }
      } else {
        promise.complete(with: Failable(error: ConcurrencyError.ownedDeallocated))
      }
    }
    self.add(handler: handler)
    return promise
  }

  final func onValue<U: ExecutionContext>(context: U, block: @escaping (Value, U) -> Void) {
    weak var weakContext = context
    let handler = FutureHandler<Value>(executor: Executor.immediate) { value in
      if let context = weakContext {
        context.executor.execute { block(value, context) }
      }
    }
    self.add(handler: handler)
  }
}

public extension Future where T : _Failable {

  final public func liftSuccess<T, U: ExecutionContext>(context: U?, transform: @escaping (Success, U) throws -> T) -> FailableFuture<T> {
    let promise = FailablePromise<T>()
    weak var weakContext = context

    self.onValue(executor: .immediate) {
      guard let successValue = $0.successValue else {
        promise.complete(with: Failable(error: $0.failureValue as! Error))
        return
      }

      guard let context = weakContext else {
        promise.complete(with: Failable(error: ConcurrencyError.ownedDeallocated))
        return
      }

      context.executor.execute {
        let transformedValue = failable { try transform(successValue, context) }
        promise.complete(with: transformedValue)
      }
    }

    return promise
  }

  final public func liftFailure<U: ExecutionContext>(context: U?, transform: @escaping (Failure, U) throws -> Success) -> FailableFuture<Success> {
    let promise = FailablePromise<Success>()
    weak var weakContext = context

    self.onValue(executor: .immediate) {
      guard let failureValue = $0.failureValue else {
        promise.complete(with: Failable(success: $0.successValue!))
        return
      }

      guard let context = weakContext else {
        promise.complete(with: Failable(error: ConcurrencyError.ownedDeallocated))
        return
      }

      context.executor.execute {
        let transformedValue = failable { try transform(failureValue, context) }
        promise.complete(with: transformedValue)
      }
    }

    return promise
  }
}

public protocol InternalQueueProvider : ExecutionContext {
  var internalQueue: DispatchQueue { get }
}

public extension InternalQueueProvider {
  var executor: Executor { return .queue(self.internalQueue) }
}
