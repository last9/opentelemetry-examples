FROM dart:stable

WORKDIR /app
COPY pubspec.yaml .
RUN dart pub get
COPY lib/ lib/
COPY bin/ bin/

CMD ["dart", "run", "bin/test_otel_dio.dart"]
