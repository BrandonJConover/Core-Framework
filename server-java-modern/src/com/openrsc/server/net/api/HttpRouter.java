package com.openrsc.server.net.api;

import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpMethod;
import io.netty.handler.codec.http.HttpResponseStatus;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.HashMap;
import java.util.Map;

/**
 * Tiny exact-match router for the JSON REST API. Maps (method, path) to a
 * functional handler. No path params, no middleware — endpoints are simple
 * enough that exact-match keeps the dispatch table readable.
 *
 * Pattern matches Express/Sinatra-style minimalism but stays inside Netty's
 * pipeline so we don't pay for a separate framework's threading model.
 *
 * Add path-prefix routing or path-param support if/when an endpoint actually
 * needs it. YAGNI for now.
 */
public final class HttpRouter {

    private static final Logger LOGGER = LogManager.getLogger("OpenRSC");

    @FunctionalInterface
    public interface Handler {
        FullHttpResponse handle(FullHttpRequest request) throws Exception;
    }

    private record Route(HttpMethod method, String path) {}

    private final Map<Route, Handler> routes = new HashMap<>();

    public HttpRouter route(HttpMethod method, String path, Handler handler) {
        routes.put(new Route(method, path), handler);
        return this;
    }

    /**
     * Dispatch an incoming request. Always returns a complete response — never
     * throws. Wraps handler exceptions as 500 with a logged stack trace.
     */
    public FullHttpResponse dispatch(FullHttpRequest request) {
        // Strip any query string before matching so /api/status?foo=1 hits /api/status.
        String uri = request.uri();
        int q = uri.indexOf('?');
        String path = q >= 0 ? uri.substring(0, q) : uri;

        Handler h = routes.get(new Route(request.method(), path));
        if (h == null) {
            // 405 vs 404: if the path exists under a different method, prefer 405.
            boolean pathExistsOtherMethod = routes.keySet().stream()
                .anyMatch(rt -> rt.path().equals(path));
            if (pathExistsOtherMethod) {
                return JsonHandler.error(HttpResponseStatus.METHOD_NOT_ALLOWED,
                    "method not allowed for " + path);
            }
            return JsonHandler.error(HttpResponseStatus.NOT_FOUND, "no such endpoint: " + path);
        }
        try {
            return h.handle(request);
        } catch (Exception e) {
            LOGGER.error("API handler failed for {} {}: {}", request.method(), path, e.getMessage(), e);
            return JsonHandler.error(HttpResponseStatus.INTERNAL_SERVER_ERROR, "internal error");
        }
    }
}
