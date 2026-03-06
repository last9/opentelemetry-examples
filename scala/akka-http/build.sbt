val scala3Version         = "3.3.4"
val pekkoVersion          = "1.1.3"
val pekkoHttpVersion      = "1.1.0"
val otelVersion           = "1.44.0"
val otelInstrumentation   = "2.10.0"

lazy val root = project
  .in(file("."))
  .settings(
    name         := "akka-http-otel-example",
    version      := "0.1.0",
    scalaVersion := scala3Version,

    libraryDependencies ++= Seq(
      // HTTP framework — Apache Pekko (drop-in replacement for Akka HTTP, Apache 2.0)
      // Akka HTTP users: swap "org.apache.pekko" -> "com.typesafe.akka" and adjust versions.
      "org.apache.pekko" %% "pekko-http"            % pekkoHttpVersion,
      "org.apache.pekko" %% "pekko-http-spray-json" % pekkoHttpVersion,
      "org.apache.pekko" %% "pekko-actor-typed"      % pekkoVersion,
      "org.apache.pekko" %% "pekko-stream"           % pekkoVersion,

      // OpenTelemetry API — SDK is provided by the Java agent at runtime
      "io.opentelemetry" % "opentelemetry-api" % otelVersion,

      // Logback appender: ships log records to the OTel collector via OTLP
      "io.opentelemetry.instrumentation" % "opentelemetry-logback-appender-1.0" %
        s"$otelInstrumentation-alpha" % Runtime,

      // Logging
      "ch.qos.logback"              % "logback-classic"    % "1.5.12",
      "com.typesafe.scala-logging" %% "scala-logging"      % "3.9.5",

      // PostgreSQL + connection pool — auto-instrumented by OTel Java agent (JDBC)
      "org.postgresql" % "postgresql" % "42.7.4",
      "com.zaxxer"     % "HikariCP"   % "5.1.0",

      // Redis — Lettuce client, auto-instrumented by OTel Java agent
      "io.lettuce" % "lettuce-core" % "6.4.0.RELEASE",

      // Kafka producer/consumer — auto-instrumented by OTel Java agent
      "org.apache.kafka" % "kafka-clients" % "3.9.0",

      // Aerospike — manual spans (not covered by OTel Java agent)
      "com.aerospike" % "aerospike-client" % "7.2.3",

      // Config and JSON
      "com.typesafe" %  "config"     % "1.4.3",
      "io.spray"    %% "spray-json"  % "1.3.6",
    ),

    // Fat JAR — required to bundle all dependencies for the Dockerfile
    assembly / assemblyJarName := "akka-http-otel.jar",
    assembly / assemblyMergeStrategy := {
      // OTel and other libraries register SPI providers in META-INF/services;
      // these must be concatenated, not discarded, or the SDK won't initialise.
      case PathList("META-INF", "services", _*) => MergeStrategy.concat
      case PathList("META-INF", _*)             => MergeStrategy.discard
      // Akka/Pekko merges reference.conf files to build the final configuration.
      case PathList("reference.conf")           => MergeStrategy.concat
      case _                                    => MergeStrategy.first
    },
  )
