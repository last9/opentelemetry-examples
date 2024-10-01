package com.example;

import java.io.IOException;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;

@WebServlet("/hello")
public class HelloServlet extends HttpServlet {
    private static final Tracer tracer = GlobalOpenTelemetry.getTracer("com.example.HelloServlet");

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        Span span = tracer.spanBuilder("HelloServlet.doGet").startSpan();
        try (Scope scope = span.makeCurrent()) {
            span.setAttribute("http.method", "GET");
            span.setAttribute("http.url", request.getRequestURL().toString());
            span.setAttribute("http.user_agent", request.getHeader("User-Agent"));

            response.setContentType("text/html");
            response.getWriter().println("<h1>Hello, OpenTelemetry!</h1>");
            
            span.setAttribute("response.status", 200);
        } finally {
            span.end();
        }
    }
}