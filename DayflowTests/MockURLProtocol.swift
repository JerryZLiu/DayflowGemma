import Foundation
import XCTest

// Based on https://www.hackingwithswift.com/articles/153/how-to-test-network-requests-with-urlprotocol

class MockURLProtocol: URLProtocol {
    // Static properties to hold our mock data
    static var mockResponse: (data: Data?, urlResponse: URLResponse?, error: Error?)?
    static var requestCompletionHandler: ((URLRequest) -> Void)? // Optional handler to inspect the request

    override class func canInit(with request: URLRequest) -> Bool {
        // We can handle all requests, or filter by URL if needed
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        // Required, but we don't need to modify the request
        return request
    }

    override func startLoading() {
        // Call the request completion handler if it's set
        if let handler = MockURLProtocol.requestCompletionHandler {
            handler(request)
        }

        if let error = MockURLProtocol.mockResponse?.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        if let urlResponse = MockURLProtocol.mockResponse?.urlResponse {
            client?.urlProtocol(self, didReceive: urlResponse, cacheStoragePolicy: .notAllowed)
        }

        if let data = MockURLProtocol.mockResponse?.data {
            client?.urlProtocol(self, didLoad: data)
        }

        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // Required, but nothing to do here for mocks
    }
} 