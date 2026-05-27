package com.example;

import com.example.api.ContestResource;
import io.undertow.Undertow;
import org.jboss.resteasy.plugins.server.undertow.UndertowJaxrsServer;
import org.jboss.resteasy.spi.ResteasyDeployment;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.ws.rs.core.Application;
import java.util.HashSet;
import java.util.Set;

public class Main {

    private static final Logger log = LoggerFactory.getLogger(Main.class);

    public static void main(String[] args) throws Exception {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8080"));

        ResteasyDeployment deployment = new ResteasyDeployment();
        deployment.setApplication(new Application() {
            @Override
            public Set<Class<?>> getClasses() {
                Set<Class<?>> classes = new HashSet<>();
                classes.add(ContestResource.class);
                return classes;
            }
        });

        Undertow.Builder builder = Undertow.builder()
                .addHttpListener(port, "0.0.0.0");

        UndertowJaxrsServer server = new UndertowJaxrsServer()
                .start(builder);
        server.deploy(deployment, "/");

        log.info("RESTEasy server started on port {}", port);
        log.info("Endpoints:");
        log.info("  GET  http://localhost:{}/api/v1/contests/42?wsId=123    (url.query test)", port);
        log.info("  POST http://localhost:{}/api/v1/contests/42/submit      (body capture + async CompletionStage)", port);
        log.info("  POST http://localhost:{}/api/v1/contests/42/fail        (async exception via writeException)", port);

        Thread.currentThread().join();
    }
}
