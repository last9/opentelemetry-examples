FROM ruby:3.3.3-slim

RUN apt-get update -qq && \
    apt-get install -y build-essential libpq-dev curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock* ./
RUN bundle install --without development test

COPY . .

EXPOSE 3001

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3001"]
