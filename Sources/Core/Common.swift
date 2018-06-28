//
//  Created by Vladimir Burdukov on 7/6/16.
//  Copyright © 2016 NetcoSports. All rights reserved.
//

import Foundation
import RxSwift

extension String: Error {
}

@available(*, deprecated, renamed: "Gnomon.Error")
public enum CommonError: Swift.Error {
  case none
}

public extension Gnomon {

  enum Error: Swift.Error {
    case undefined(message: String?)
    case nonHTTPResponse(response: URLResponse)
    case invalidResponse
    case unableToParseModel(Swift.Error)
    case invalidURL(urlString: String)
    case errorStatusCode(Int, Data)
  }

}

extension HTTPURLResponse {

  private static var cacheFlagKey = "X-ResultFromHttpCache"

  var httpCachedResponse: HTTPURLResponse? {
    guard let url = url else { return nil }
    var headers = allHeaderFields as? [String: String] ?? [:]
    headers[HTTPURLResponse.cacheFlagKey] = "true"
    return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)
  }

  var resultFromHTTPCache: Bool {
    guard let headers = allHeaderFields as? [String: String] else { return false }
    return headers[HTTPURLResponse.cacheFlagKey] == "true"
  }

}

// swiftlint:disable:next cyclomatic_complexity
internal func prepareDataRequest<U>(from request: Request<U>,
                                    cachePolicy: URLRequest.CachePolicy) throws -> URLRequest {
  guard let url = URL(string: request.URLString) else { throw Gnomon.Error.invalidURL(urlString: request.URLString) }
  var dataRequest = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: request.timeout)
  dataRequest.httpMethod = request.method.rawValue
  if let headers = request.headers {
    for (key, value) in headers {
      dataRequest.setValue(value, forHTTPHeaderField: key)
    }
  }

  switch (request.method.canHaveBody, request.params) {
  case (true, .none), (false, .none):
    dataRequest.url = try prepareURL(from: request, params: nil)
  case (false, let .urlEncoded(params)):
    dataRequest.url = try prepareURL(from: request, params: params)
  case (false, .json), (false, .multipart):
    throw "can't encode \(request.method.rawValue) request params as JSON or multipart"
  case (false, .data):
    throw "can't add binary body to \(request.method.rawValue) request"
  case (true, let .urlEncoded(params)):
    let queryItems = prepare(value: params, with: nil)
    var components = URLComponents()
    components.queryItems = queryItems
    dataRequest.httpBody = components.percentEncodedQuery?.data(using: String.Encoding.utf8)
    dataRequest.url = try prepareURL(from: request, params: nil)
    dataRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
  case (true, let .json(params)):
    dataRequest.httpBody = try JSONSerialization.data(withJSONObject: params, options: [])
    dataRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    dataRequest.url = try prepareURL(from: request, params: nil)
  case (true, let .multipart(form, files)):
    let (data, contentType) = try prepareMultipartData(with: form, files)
    dataRequest.httpBody = data
    dataRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
    dataRequest.url = try prepareURL(from: request, params: nil)
  case (true, let .data(data, contentType)):
    dataRequest.httpBody = data
    dataRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
    dataRequest.url = try prepareURL(from: request, params: nil)
  }

  dataRequest.httpShouldHandleCookies = request.shouldHandleCookies

  return dataRequest
}

internal func prepareURL<T>(from request: Request<T>, params: [String: Any]?) throws -> URL {
  var queryItems = [URLQueryItem]()
  if let params = params {
    queryItems.append(contentsOf: prepare(value: params, with: nil))
  }

  guard var components = URLComponents(string: request.URLString) else {
    throw "can't parse provided URL: \(request.URLString)"
  }
  queryItems.append(contentsOf: components.queryItems ?? [])
  components.queryItems = queryItems.count > 0 ? queryItems : nil
  guard let url = components.url else { throw "can't prepare URL from components: \(components)" }
  return url
}

private func prepare(value: Any, with key: String?) -> [URLQueryItem] {
  switch value {
  case let dictionary as [String: Any]:
    return dictionary.sorted { $0.0 < $1.0 }.flatMap { nestedKey, nestedValue -> [URLQueryItem] in
      if let key = key {
        return prepare(value: nestedValue, with: "\(key)[\(nestedKey)]")
      } else {
        return prepare(value: nestedValue, with: nestedKey)
      }
    }
  case let array as [Any]:
    if let key = key {
      return array.flatMap { prepare(value: $0, with: "\(key)[]") }
    } else {
      return []
    }
  case let string as String:
    if let key = key {
      return [URLQueryItem(name: key, value: string)]
    } else {
      return []
    }
  case let stringConvertible as CustomStringConvertible:
    if let key = key {
      return [URLQueryItem(name: key, value: stringConvertible.description)]
    } else {
      return []
    }
  default: return []
  }
}

internal func prepareMultipartData(with form: [String: String],
                                   _ files: [String: MultipartFile]) throws -> (data: Data, contentType: String) {
  let boundary = "__X_NST_BOUNDARY__"
  var data = Data()
  guard let boundaryData = "--\(boundary)\r\n".data(using: .utf8) else { throw "can't encode boundary" }
  for (key, value) in form {
    data.append(boundaryData)
    guard let dispositionData = "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8) else {
      throw "can't encode key \(key)"
    }
    data.append(dispositionData)
    guard let valueData = (value.description + "\r\n").data(using: .utf8) else { throw "can't encode value \(value)" }
    data.append(valueData)
  }

  for (key, file) in files {
    data.append(boundaryData)
    guard let dispositionData = "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(file.filename)\"\r\n"
      .data(using: .utf8) else { throw "can't encode key \(key)" }
    data.append(dispositionData)
    guard let contentTypeData = "Content-Type: \(file.contentType)\r\n\r\n".data(using: .utf8) else {
      throw "can't encode content-type \(file.contentType)"
    }
    data.append(contentTypeData)
    data.append(file.data)
    guard let carriageReturnData = "\r\n".data(using: .utf8) else {
      throw "can't encode carriage return"
    }
    data.append(carriageReturnData)
  }

  guard let closingBoundaryData = "--\(boundary)--\r\n".data(using: .utf8) else {
    throw "can't encode closing boundary"
  }
  data.append(closingBoundaryData)
  return (data, "multipart/form-data; boundary=\(boundary)")
}

internal func processedResult<U>(from data: Data, for request: Request<U>) throws -> U {
  let container = try U.dataContainer(with: data, at: request.xpath)
  return try U(container)
}

internal func validated(response: Any) throws -> (result: [String: Any], isArray: Bool) {
  switch response {
  case let dictionary as [String: Any]: return (dictionary, false)
  case let array as [AnyObject]: return (["array": array], true)
  default: throw Gnomon.Error.invalidResponse
  }
}

public typealias Interceptor = (URLRequest) -> URLRequest

public enum Result<T> {
  case ok(T)
  case error(Error)
}

public extension Result {

  var value: T? {
    switch self {
    case let .ok(value): return value
    case .error: return nil
    }
  }

  var error: Error? {
    switch self {
    case .ok: return nil
    case let .error(error): return error
    }
  }

  func map<U>(_ transform: (T) throws -> U) rethrows -> Result<U> {
    switch self {
    case let .ok(value):
      return .ok(try transform(value))
    case let .error(error):
      return .error(error)
    }
  }

  func value(or `default`: T) -> T {
    switch self {
    case let .ok(value): return value
    case .error: return `default`
    }
  }

}

extension ObservableType {

  func asResult() -> Observable<Result<E>> {
    return materialize().map { event -> Event<Result<E>> in
      switch event {
      case let .next(element): return .next(.ok(element))
      case let .error(error): return .next(.error(error))
      case .completed: return .completed
      }
    }.dematerialize()
  }

}
