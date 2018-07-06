//
//  LoggingSpec.swift
//  Tests
//
//  Created by Vladimir Burdukov on 11/9/17.
//
//

import XCTest
import Nimble
import RxSwift
import RxBlocking
import SwiftyJSON

@testable import Gnomon

class LoggingSpec: XCTestCase {

  override func setUp() {
    super.setUp()

    Nimble.AsyncDefaults.Timeout = 7
    URLCache.shared.removeAllCachedResponses()

    Gnomon.logging = false
    Gnomon.log = { string in
      print(string)
    }
  }

  func request(global: Bool? = nil, request reqLogging: Bool? = nil) {
    if let global = global {
      Gnomon.logging = global
    }
    do {
      let request = try Request<TestModel5>(URLString: "\(Params.API.baseURL)/get?key=123")
        .setMethod(.GET)

      if let reqLogging = reqLogging {
        request.debugLogging = reqLogging
      }

      guard let response = try Gnomon.models(for: request).toBlocking().first() else { throw "can't extract response" }
      expect(response.result.key).to(equal(123))
    } catch {
      fail("\(error)")
    }
  }

  func testDefaultState() {
    var log: String? = nil

    Gnomon.log = { string in
      log = log ?? "" + string + "\n"
    }

    request()
    expect(log).to(beNil())
  }

  func testDisabledState() {
    Gnomon.logging = false
    testDefaultState()
  }

  func testEnabledLogging() {
    var log: String? = nil

    Gnomon.log = { string in
      log = log ?? "" + string + "\n"
    }

    request(global: true)
    expect(log) == "curl -X GET --compressed \"\(Params.API.baseURL)/get?key=123\"\n"
  }

  func testEnabledLoggingAndDisabledRequestLogging() {
    var log: String? = nil

    Gnomon.log = { string in
      log = log ?? "" + string + "\n"
    }

    request(global: true, request: false)
    expect(log).to(beNil())
  }

  func testDisabledLoggingAndEnabledRequestLogging() {
    var log: String? = nil

    Gnomon.log = { string in
      log = log ?? "" + string + "\n"
    }

    request(global: false, request: true)
    expect(log) == "curl -X GET --compressed \"\(Params.API.baseURL)/get?key=123\"\n"
  }

  func testDisabledLoggingAndDisabledRequestLogging() {
    var log: String? = nil

    Gnomon.log = { string in
      log = log ?? "" + string + "\n"
    }

    request(global: false, request: false)
    expect(log).to(beNil())
  }

}
