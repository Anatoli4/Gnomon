//
//  ChainRequestSpec.swift
//  Gnomon
//
//  Created by Vladimir Burdukov on 7/26/16.
//  Copyright © 2016 NetcoSports. All rights reserved.
//

import XCTest
import Nimble
import RxSwift
import RxBlocking

@testable import Gnomon

class ChainRequestSpec: XCTestCase {

  override func setUp() {
    super.setUp()

    Nimble.AsyncDefaults.Timeout = 7
    URLCache.shared.removeAllCachedResponses()
  }

  func testChainRequest() {
    do {
      let request = try RequestBuilder<TestModel1>()
        .setURLString("\(Params.API.baseURL)/get?key=123")
        .setMethod(.GET).setXPath("args").build()

      let response = try Gnomon.models(for: request)
        .flatMap { response -> Observable<Response<TestModel2>> in
          let otherKey = response.result.key + 1
          let nextRequest = try RequestBuilder<TestModel2>()
            .setURLString("\(Params.API.baseURL)/get?otherKey=\(otherKey)")
            .setMethod(.GET).setXPath("args").build()

          return Gnomon.models(for: nextRequest)
        }.toBlocking().first()

      expect(response).toNot(beNil())
      expect(response?.result.otherKey).to(equal(124))
    } catch {
      fail("\(error)")
      return
    }
  }

}
