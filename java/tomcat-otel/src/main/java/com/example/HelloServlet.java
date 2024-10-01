package com.example;

   import java.io.IOException;
   import javax.servlet.ServletException;
   import javax.servlet.annotation.WebServlet;
   import javax.servlet.http.HttpServlet;
   import javax.servlet.http.HttpServletRequest;
   import javax.servlet.http.HttpServletResponse;

   import io.opentelemetry.api.GlobalOpenTelemetry;
   import io.opentelemetry.api.trace.Span;
   import io.opentelemetry.api.trace.Tracer;

   @WebServlet("/hello")
   public class HelloServlet extends HttpServlet {
       private static final Tracer tracer = GlobalOpenTelemetry.getTracer("com.example.HelloServlet");

       @Override
       protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
           Span span = tracer.spanBuilder("HelloServlet.doGet").startSpan();
           try {
               response.setContentType("text/html");
               response.getWriter().println("<h1>Hello, OpenTelemetry!</h1>");
           } finally {
               span.end();
           }
       }
   }