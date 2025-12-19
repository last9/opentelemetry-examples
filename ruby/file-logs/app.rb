require 'logger'
require 'json'
require 'time'

# Create logs directory if it doesn't exist
Dir.mkdir('logs') unless Dir.exist?('logs')

# Initialize logger to write to a file
logger = Logger.new('logs/application.log', 'daily')
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  {
    timestamp: datetime.strftime('%Y-%m-%dT%H:%M:%S%z'),
    level: severity,
    message: msg,
    service: 'ruby-app'
  }.to_json + "\n"
end

# Simulate application activity with different log levels
puts "Starting Ruby application. Writing logs to logs/application.log"
puts "Press Ctrl+C to stop"

counter = 0
begin
  loop do
    counter += 1

    case counter % 4
    when 0
      logger.info("User request processed successfully - Request ID: #{rand(1000..9999)}")
    when 1
      logger.warn("High memory usage detected - #{rand(70..90)}%")
    when 2
      logger.info("Database query executed - Duration: #{rand(10..100)}ms")
    when 3
      logger.error("Failed to connect to external API - Retrying...")
    end

    sleep 2
  end
rescue Interrupt
  logger.info("Application shutting down")
  puts "\nApplication stopped"
end
