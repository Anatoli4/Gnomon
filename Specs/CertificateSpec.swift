//
//  CertificateSpec.swift
//  Tests
//
//  Created by Vladimir Burdukov on 27/8/17.
//
//

import XCTest
import Gnomon
import Nimble
import RxBlocking

class CertificateSpec: XCTestCase {

  override func setUp() {
    super.setUp()

    Nimble.AsyncDefaults.Timeout = 7
    URLCache.shared.removeAllCachedResponses()
    Gnomon.removeAllInterceptors()
  }

  func testInvalidCertificate() {
    do {
      let builder = RequestBuilder<String>()
        .setURLString("https://self-signed.badssl.com/").setMethod(.GET)
      builder.setAuthenticationChallenge { challenge, completionHandler -> Void in
        completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
      }
      let request = try builder.build()

      guard let response = try Gnomon.models(for: request).toBlocking().first() else {
        return fail("can't extract response")
      }

      expect(response.result.count).to(beGreaterThan(0))
    } catch {
      fail("\(error)")
      return
    }
  }

  func testInvalidCertificateWithoutHandler() {
    var err: NSError?
    do {
      let builder = RequestBuilder<String>()
        .setURLString("https://self-signed.badssl.com/").setMethod(.GET)
      let request = try builder.build()

      let result = try Gnomon.models(for: request).toBlocking().first()
      expect(result).to(beNil())
    } catch let e where e is String {
      fail("\(e)")
    } catch {
      err = error as NSError
      expect(err).toNot(beNil())
    }
  }

}
