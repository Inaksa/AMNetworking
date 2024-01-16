import Foundation
import AMCache

public enum NetworkError: Error {
    case InvalidURL
    case InvalidServerResponse
    case UnableToDecodeError
}

public enum HTTPVerb {
    case GET
    case POST
    case UPDATE
    case DELETE
    case PUT
}

public class RequestBuilder<T: Decodable> {
    let url: String
    let verb: String
    let body: String?
    
    public init(url: String, httpVerb: HTTPVerb = .GET, body: String? = nil) {
        self.url = url
        self.verb = "\(httpVerb)"
        self.body = body
    }
}

public class AMNetworkingManager {
    static public let instance: AMNetworkingManager = AMNetworkingManager()
    private init() {}
    
    private var downloadTask: URLSessionDataTask?
    private var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil

        return URLSession(configuration: config)
    }()
    
    private var cache: AMCache = AMCache()
    
    public func cancelPendingRequests() {
        if downloadTask?.state == .running || downloadTask?.state == .suspended {
            downloadTask?.cancel()
        }
    }
    
    public func performRequest<T: Codable>(_ req: RequestBuilder<T>, success: @escaping (T) -> Void, failure: @escaping (Error) -> Void) {
        if let storedData = cache.getCachedValue(for: req.url),
           let cachedValue = try? JSONDecoder().decode(T.self, from: storedData) {
            success(cachedValue)
            return
        }
        
        guard let url = URL(string: req.url) else {
            failure(NetworkError.InvalidURL)
            return
        }
        
        var httpRequest: URLRequest = URLRequest(url: url)
        httpRequest.httpMethod = req.verb
        httpRequest.cachePolicy = .reloadRevalidatingCacheData
        
        if let body = req.body, let bodyData = body.data(using: .utf8) {
            httpRequest.httpBody = bodyData
        }
       
        downloadTask = urlSession.dataTask(with: httpRequest, completionHandler: { data, response, err in
            guard err == nil else { failure(err!); return }
            guard let data = data else {
                failure(NetworkError.InvalidServerResponse)
                return
            }
            
            do {
                // Save in cache
                self.cache.cacheValue(key: req.url, value: data)
                
                let retValue = try JSONDecoder().decode(T.self, from: data)
                success(retValue)
            } catch {
                print(url.absoluteString)
                failure(NetworkError.UnableToDecodeError)
                return
            }
        })

        downloadTask?.resume()
    }
    
    public func performRequest<T: Codable>(_ req: RequestBuilder<T>) async throws -> T {

        guard let url = URL(string: req.url) else {
            throw NSError(domain: "NetworkingError", code: NSURLErrorBadURL)
        }

        // Use the async variant of URLSession to fetch data
        // Code might suspend here
        let (data, _) = try await URLSession.shared.data(from: url)

        // Parse the JSON data
        let retValue = try JSONDecoder().decode(T.self, from: data)
        return retValue
    }
}
