package com.example;

   import io.opentelemetry.api.GlobalOpenTelemetry;
   import io.opentelemetry.api.OpenTelemetry;
   import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
   import io.opentelemetry.sdk.OpenTelemetrySdk;
   import io.opentelemetry.sdk.trace.SdkTracerProvider;
   import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;

   import javax.servlet.ServletContextEvent;
   import javax.servlet.ServletContextListener;
   import javax.servlet.annotation.WebListener;

   @WebListener
   public class OpenTelemetryConfig implements ServletContextListener {

       @Override
       public void contextInitialized(ServletContextEvent sce) {
           OpenTelemetry openTelemetry = initializeOpenTelemetry();
           GlobalOpenTelemetry.set(openTelemetry);
       }

       private static OpenTelemetry initializeOpenTelemetry() {
           OtlpGrpcSpanExporter spanExporter = OtlpGrpcSpanExporter.builder()
                   .setEndpoint("http://localhost:4317")
                   .build();

           SdkTracerProvider sdkTracerProvider = SdkTracerProvider.builder()
                   .addSpanProcessor(BatchSpanProcessor.builder(spanExporter).build())
                   .build();

           return OpenTelemetrySdk.builder()
                   .setTracerProvider(sdkTracerProvider)
                   .buildAndRegisterGlobal();
       }

       @Override
       public void contextDestroyed(ServletContextEvent sce) {
           // Perform cleanup if necessary
       }
   }