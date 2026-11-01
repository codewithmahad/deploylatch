
package dev.deploylatch.demo;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

public final class DemoServer {

    private static final String VERSION = "v1";
    private static final int PORT = 8080;

    public static void main(String[] args) throws IOException {

        HttpServer server = HttpServer.create(
                new InetSocketAddress("127.0.0.1", PORT), 0
        );

        server.createContext("/health", exchange ->
                respond(exchange, "/health", "OK\n"));

        server.createContext("/version", exchange ->
                respond(exchange, "/version", VERSION + "\n"));

        server.start();

        System.out.println(
                "Demo app " + VERSION + " running on http://127.0.0.1:" + PORT
        );
    }

    private static void respond(
            HttpExchange exchange,
            String expectedPath,
            String body
    ) throws IOException {

        if (!expectedPath.equals(exchange.getRequestURI().getPath())) {
            exchange.sendResponseHeaders(404, -1);
            exchange.close();
            return;
        }

        if (!"GET".equals(exchange.getRequestMethod())) {
            exchange.getResponseHeaders().set("Allow", "GET");
            exchange.sendResponseHeaders(405, -1);
            exchange.close();
            return;
        }

        byte[] response = body.getBytes(StandardCharsets.UTF_8);

        exchange.getResponseHeaders().set(
                "Content-Type", "text/plain; charset=utf-8"
        );

        exchange.sendResponseHeaders(200, response.length);

        try (OutputStream output = exchange.getResponseBody()) {
            output.write(response);
        }
    }
}
