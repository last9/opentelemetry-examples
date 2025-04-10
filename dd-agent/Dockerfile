FROM ruby:3.2-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Ruby dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy application files
COPY . .

# Expose port
EXPOSE 3000

# Start the application
CMD ["ruby", "app.rb"] 