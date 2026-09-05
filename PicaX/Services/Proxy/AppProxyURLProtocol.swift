import Foundation

private nonisolated final class URLProtocolAsyncResultBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func take() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let value = result
        result = nil
        return value
    }
}

// Request encoding and callbacks run on one worker; cancellation and active
// transport references shared with URLSession are protected by stateLock.
nonisolated final class AppProxyURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest ?? task.originalRequest else {
            return false
        }
        return canInit(with: request)
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        guard let body = request.httpBody,
              URLProtocol.property(
                forKey: preservedBodyProperty,
                in: request
              ) == nil,
              let mutableRequest = (
                request as NSURLRequest
              ).mutableCopy() as? NSMutableURLRequest else {
            return request
        }
        URLProtocol.setProperty(
            body,
            forKey: preservedBodyProperty,
            in: mutableRequest
        )
        return mutableRequest as URLRequest
    }

    override init(
        request: URLRequest,
        cachedResponse: CachedURLResponse?,
        client: URLProtocolClient?
    ) {
        preservedBody = Self.body(from: request)
        super.init(
            request: request,
            cachedResponse: cachedResponse,
            client: client
        )
    }

    override func startLoading() {
        preservedBody = preservedBody
            ?? Self.body(from: task?.currentRequest)
            ?? Self.body(from: task?.originalRequest)
        let thread = Thread { [weak self] in
            self?.performRequest()
        }
        thread.name = "work.picax.app-proxy.url-protocol"
        workerThread = thread
        thread.start()
    }

    override func stopLoading() {
        stateLock.lock()
        cancelled = true
        let channel = activeChannel
        let tunnel = activeTunnel
        stateLock.unlock()
        channel?.close()
        tunnel?.close()
    }

    private func performRequest() {
        guard !isCancelled else { return }

        do {
            guard let token = request.value(
                forHTTPHeaderField: AppProxyRouteRegistry.headerName
            ), let route = AppProxyRouteRegistry.shared.route(
                for: token
            ) else {
                throw AppProxyError.configurationMissing
            }
            AppProxyConnectionThrottle.shared.acquire(route: route)
            defer {
                AppProxyConnectionThrottle.shared.release(route: route)
            }
            guard !isCancelled else { return }
            guard let url = request.url,
                  let host = url.host,
                  let scheme = url.scheme?.lowercased() else {
                throw AppProxyError.invalidHTTPResponse(
                    "请求地址缺少主机名"
                )
            }
            let portValue = url.port
                ?? (scheme == "http" ? 80 : 443)
            guard let port = UInt16(exactly: portValue) else {
                throw AppProxyError.invalidPort
            }

            let tunnel = try waitForAsync {
                try await AppProxyConnector.openTunnel(
                    route: route,
                    destinationHost: host,
                    destinationPort: port
                )
            }
            setActiveTunnel(tunnel)
            defer { tunnel.close() }
            guard !isCancelled else { return }

            let channel: AppProxyHTTPChannel
            if scheme == "https" {
                let tls = AppProxyTLS(
                    tunnel: tunnel,
                    hostname: host,
                    proxyDescription: route.diagnosticDescription
                )
                try tls.handshake()
                channel = AppProxySecureHTTPChannel(tls: tls)
            } else {
                channel = AppProxyPlainHTTPChannel(tunnel: tunnel)
            }
            setActiveChannel(channel)
            defer { channel.close() }

            let encodedRequest = try AppProxyHTTPCodec.encodedRequest(
                request,
                preservedBody: preservedBody,
                internalHeaderName: AppProxyRouteRegistry.headerName
            )
            try channel.write(encodedRequest)
            let response = try AppProxyHTTPCodec.readResponse(
                from: channel,
                requestMethod: request.httpMethod ?? "GET"
            )
            guard !isCancelled else { return }
            guard let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: response.version,
                headerFields: response.headers
            ) else {
                throw AppProxyError.invalidHTTPResponse(
                    "无法构建 HTTP 响应"
                )
            }

            if let redirect = try redirectRequest(
                for: response,
                originalRequest: request
            ) {
                client?.urlProtocol(
                    self,
                    wasRedirectedTo: redirect,
                    redirectResponse: httpResponse
                )
                return
            }

            client?.urlProtocol(
                self,
                didReceive: httpResponse,
                cacheStoragePolicy: .notAllowed
            )
            if !response.body.isEmpty {
                client?.urlProtocol(self, didLoad: response.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            guard !isCancelled else { return }
            client?.urlProtocol(
                self,
                didFailWithError: AppProxyTransportError(error)
            )
        }
    }

    private func redirectRequest(
        for response: AppProxyHTTPResponse,
        originalRequest: URLRequest
    ) throws -> URLRequest? {
        let redirectCodes = Set([301, 302, 303, 307, 308])
        guard redirectCodes.contains(response.statusCode),
              let location = response.headers["location"],
              let sourceURL = originalRequest.url,
              let targetURL = URL(
                string: location,
                relativeTo: sourceURL
              )?.absoluteURL,
              let targetScheme = targetURL.scheme?.lowercased(),
              targetScheme == "http" || targetScheme == "https" else {
            return nil
        }
        if sourceURL.scheme?.lowercased() == "https",
           targetScheme != "https" {
            throw AppProxyError.invalidHTTPResponse(
                "已阻止 HTTPS 降级重定向"
            )
        }

        let originalMethod = (
            originalRequest.httpMethod ?? "GET"
        ).uppercased()
        let preservesMethod =
            response.statusCode == 307 || response.statusCode == 308
        let redirectedMethod: String
        if originalMethod == "HEAD" {
            redirectedMethod = "HEAD"
        } else if preservesMethod {
            redirectedMethod = originalMethod
        } else {
            redirectedMethod = "GET"
        }

        var redirected = URLRequest(
            url: targetURL,
            cachePolicy: originalRequest.cachePolicy,
            timeoutInterval: originalRequest.timeoutInterval
        )
        redirected.httpMethod = redirectedMethod
        if preservesMethod {
            redirected.httpBody = preservedBody
        }

        let sameOrigin = origin(of: sourceURL) == origin(of: targetURL)
        let sensitiveHeaders = Set([
            "authorization",
            "cookie",
            "proxy-authorization"
        ])
        let generatedHeaders = Set([
            "host",
            "content-length",
            "connection",
            "transfer-encoding",
            AppProxyRouteRegistry.headerName.lowercased()
        ])
        for (name, value) in originalRequest.allHTTPHeaderFields ?? [:] {
            let lowercaseName = name.lowercased()
            guard !generatedHeaders.contains(lowercaseName),
                  sameOrigin
                    || !sensitiveHeaders.contains(lowercaseName) else {
                continue
            }
            if redirectedMethod == "GET",
               lowercaseName == "content-type" {
                continue
            }
            redirected.setValue(value, forHTTPHeaderField: name)
        }
        guard let token = originalRequest.value(
            forHTTPHeaderField: AppProxyRouteRegistry.headerName
        ) else {
            throw AppProxyError.configurationMissing
        }
        redirected.setValue(
            token,
            forHTTPHeaderField: AppProxyRouteRegistry.headerName
        )
        return redirected
    }

    private func origin(of url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }

    private func waitForAsync<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = URLProtocolAsyncResultBox<T>()
        Task {
            do {
                resultBox.store(.success(try await operation()))
            } catch {
                resultBox.store(.failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result = resultBox.take() else {
            throw AppProxyError.connectionClosed
        }
        return try result.get()
    }

    private func setActiveTunnel(_ tunnel: AppProxyByteTunnel) {
        stateLock.lock()
        activeTunnel = tunnel
        let shouldClose = cancelled
        stateLock.unlock()
        if shouldClose {
            tunnel.close()
        }
    }

    private func setActiveChannel(_ channel: AppProxyHTTPChannel) {
        stateLock.lock()
        activeChannel = channel
        let shouldClose = cancelled
        stateLock.unlock()
        if shouldClose {
            channel.close()
        }
    }

    private static func body(from request: URLRequest?) -> Data? {
        guard let request else { return nil }
        return request.httpBody
            ?? URLProtocol.property(
                forKey: preservedBodyProperty,
                in: request
            ) as? Data
    }

    private static let preservedBodyProperty =
        "work.picax.app-proxy.preserved-body"

    private var preservedBody: Data?
    private var workerThread: Thread?
    private let stateLock = NSLock()
    private var cancelled = false
    private var activeTunnel: AppProxyByteTunnel?
    private var activeChannel: AppProxyHTTPChannel?

    private var isCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelled
    }
}
