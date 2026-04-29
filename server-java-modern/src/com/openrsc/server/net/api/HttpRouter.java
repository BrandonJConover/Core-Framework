package com.openrsc.server.net.api;

import io.netty.handler.codec.http.FullHttpRequest;
import io.netty.handler.codec.http.FullHttpResponse;
import io.netty.handler.codec.http.HttpMethod;
import io.netty.handler.codec.http.HttpResponseStatus;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Router for the JSON REST API. Supports two path styles:
 *
 *   exact:           "/api/status"
 *   parameterised:   "/api/character/{username}"
 *
 * Exact matches always win over parameterised matches; if /foo/{x} and
 * /foo/bar both exist, /foo/bar resolves to the exact handler.
 *
 * Parameterised segments use {name} placeholders. Names extracted from the
 * URL are passed to {@link ParamHandler} as a Map. Placeholders match a
 * single non-empty path segment (no slashes); an empty segment fails to
 * match.
 *
 * 404 vs 405 are still distinguished — if the path exists under a different
 * method (exact or parameterised), the response is 405; otherwise 404.
 */
public final class HttpRouter {

    private static final Logger LOGGER = LogManager.getLogger("OpenRSC");

    @FunctionalInterface
    public interface Handler {
        FullHttpResponse handle(FullHttpRequest request) throws Exception;
    }

    /** Variant for parameterised routes — receives the extracted path-param map. */
    @FunctionalInterface
    public interface ParamHandler {
        FullHttpResponse handle(FullHttpRequest request, Map<String, String> pathParams) throws Exception;
    }

    private record ExactRoute(HttpMethod method, String path) {}

    private record ParamRoute(HttpMethod method, String original,
                              Pattern pattern, List<String> varNames,
                              ParamHandler handler) {}

    private final Map<ExactRoute, Handler> exactRoutes = new HashMap<>();
    private final List<ParamRoute> paramRoutes = new ArrayList<>();

    public HttpRouter route(HttpMethod method, String path, Handler handler) {
        if (path.indexOf('{') >= 0) {
            // Caller used Handler signature for a parameterised path; wrap it.
            return route(method, path, (req, params) -> handler.handle(req));
        }
        exactRoutes.put(new ExactRoute(method, path), handler);
        return this;
    }

    public HttpRouter route(HttpMethod method, String pattern, ParamHandler handler) {
        if (pattern.indexOf('{') < 0) {
            // Pattern has no placeholders; register on the exact map for fast lookup.
            exactRoutes.put(new ExactRoute(method, pattern), req -> handler.handle(req, Map.of()));
            return this;
        }
        paramRoutes.add(compile(method, pattern, handler));
        return this;
    }

    /**
     * Compile a {var}-style pattern into a regex with capturing groups and
     * a list of variable names in declaration order.
     *
     * "/api/character/{username}" -> ^/api/character/([^/]+)$  with names=[username]
     */
    private static ParamRoute compile(HttpMethod method, String pattern, ParamHandler handler) {
        StringBuilder regex = new StringBuilder("^");
        List<String> names = new ArrayList<>();
        int i = 0;
        while (i < pattern.length()) {
            char c = pattern.charAt(i);
            if (c == '{') {
                int end = pattern.indexOf('}', i);
                if (end < 0) {
                    throw new IllegalArgumentException("unterminated path parameter in " + pattern);
                }
                String name = pattern.substring(i + 1, end);
                if (name.isEmpty()) {
                    throw new IllegalArgumentException("empty path parameter name in " + pattern);
                }
                names.add(name);
                regex.append("([^/]+)");
                i = end + 1;
            } else {
                // Escape regex metachars; URL paths don't use them legitimately.
                if ("\\.+*?()|[]^$".indexOf(c) >= 0) regex.append('\\');
                regex.append(c);
                i++;
            }
        }
        regex.append("$");
        return new ParamRoute(method, pattern, Pattern.compile(regex.toString()), names, handler);
    }

    /**
     * Dispatch an incoming request. Always returns a complete response — never
     * throws. Wraps handler exceptions as 500 with a logged stack trace.
     */
    public FullHttpResponse dispatch(FullHttpRequest request) {
        // Strip any query string before matching.
        String uri = request.uri();
        int q = uri.indexOf('?');
        String path = q >= 0 ? uri.substring(0, q) : uri;

        // Exact match first.
        Handler exact = exactRoutes.get(new ExactRoute(request.method(), path));
        if (exact != null) {
            return run(request, path, () -> exact.handle(request));
        }

        // Parameterised match.
        for (ParamRoute pr : paramRoutes) {
            if (!pr.method().equals(request.method())) continue;
            Matcher m = pr.pattern().matcher(path);
            if (m.matches()) {
                Map<String, String> params = new LinkedHashMap<>();
                for (int i = 0; i < pr.varNames().size(); i++) {
                    params.put(pr.varNames().get(i), m.group(i + 1));
                }
                return run(request, path, () -> pr.handler().handle(request, params));
            }
        }

        // Path not found in either map. Distinguish 405 vs 404.
        boolean pathExistsOtherMethod =
            exactRoutes.keySet().stream().anyMatch(rt -> rt.path().equals(path)) ||
            paramRoutes.stream().anyMatch(pr -> pr.pattern().matcher(path).matches());
        if (pathExistsOtherMethod) {
            return JsonHandler.error(HttpResponseStatus.METHOD_NOT_ALLOWED,
                "method not allowed for " + path);
        }
        return JsonHandler.error(HttpResponseStatus.NOT_FOUND, "no such endpoint: " + path);
    }

    /** Common error-handling wrapper for handler invocation. */
    private static FullHttpResponse run(FullHttpRequest request, String path, ThrowingSupplier work) {
        try {
            return work.get();
        } catch (Exception e) {
            LOGGER.error("API handler failed for {} {}: {}",
                request.method(), path, e.getMessage(), e);
            return JsonHandler.error(HttpResponseStatus.INTERNAL_SERVER_ERROR, "internal error");
        }
    }

    @FunctionalInterface
    private interface ThrowingSupplier {
        FullHttpResponse get() throws Exception;
    }
}
