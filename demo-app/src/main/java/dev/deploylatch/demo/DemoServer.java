package dev.deploylatch.demo;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Properties;

public final class DemoServer {

    private static final int PORT = 8080;

    private DemoServer() {
    }

    public static void main(String[] args) throws IOException {
        Properties release = new Properties();

        try (InputStream input = DemoServer.class.getResourceAsStream("/release.properties")) {
            if (input == null) {
                throw new IllegalStateException("Missing release.properties in the JAR");
            }
            release.load(input);
        }

        String version = release.getProperty("version", "").trim();
        String healthyValue = release.getProperty("healthy", "").trim();

        if (version.isEmpty() || (!healthyValue.equals("true") && !healthyValue.equals("false"))) {
            throw new IllegalStateException("Invalid release.properties");
        }

        boolean healthy = Boolean.parseBoolean(healthyValue);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", PORT), 0);

        server.createContext("/health", exchange ->
                respond(exchange, "/health", healthy ? 200 : 503,
                        healthy ? "OK\n" : "UNHEALTHY\n"));

        server.createContext("/version", exchange ->
                respond(exchange, "/version", 200, version + "\n"));

        server.start();
        System.out.printf("Demo app %s listening on 127.0.0.1:%d%n", version, PORT);
    }

    private static void respond(HttpExchange exchange, String expectedPath,
                                int status, String body) throws IOException {
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

        byte[] content = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "text/plain; charset=utf-8");
        exchange.sendResponseHeaders(status, content.length);

        try (OutputStream output = exchange.getResponseBody()) {
            output.write(content);
        }
    }
}
