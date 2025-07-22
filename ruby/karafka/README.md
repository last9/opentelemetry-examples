# Karafka 2.4 non Rails example application

> Note: Credits for sample application code: https://github.com/karafka/example-apps/tree/master/v2.4-non-rails

This is an example application which uses:

- [Karafka framework](https://github.com/karafka/karafka) `2.4` to receive messages from [Apache Kafka](http://kafka.apache.org/) server
- [WaterDrop gem](https://github.com/karafka/waterdrop) to send messages back to Kafka
- [Karafka-Testing](https://github.com/karafka/testing) provides RSpec helpers, to make testing of Karafka consumers much easier
- [OpenTelemetry Ruby SDK] to demonstrate how to instrument a Karafka app using OpenTelemetry

## Usage

Please run `bundle install` to install all the dependencies.

After that, following commands are available. You should run them in the console.

Create all needed topics:

```
bundle exec karafka topics migrate
```

Run Karafka server to consume messages, process and send messages:

```
bundle exec karafka s
```

Generate initial messages to Kafka server by sending them using WaterDrop:

```
bundle exec rake waterdrop:send
```

You can also run RSpec specs to see how the testing RSpec library integrates with RSpec:

```
bundle exec rspec spec
```

### Setting up OpenTelemetry

Refer to `lib/otel_setup.rb` file. It is called in `karafka.rb` as `OtelSetup.new.process` to setup the OpenTelemetry instrumentation.

Set following environment variables:

``` shell
OTEL_SERVICE_NAME=<your-app-name>
OTEL_EXPORTER_OTLP_ENDPOINT=<last9_otlp_endpoint>
OTEL_EXPORTER_OTLP_HEADERS="Authorization=<last9_auth_header>"
OTEL_TRACES_EXPORTER=otlp
```

Once the application is started, it will start sending traces to Last9.
