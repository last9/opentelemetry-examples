require_relative "boot"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module StripePaymentsApi
  class Application < Rails::Application
    config.load_defaults 7.1
    config.api_only = true

    # dotenv-rails 3.x auto-loads as a Railtie — no manual load needed
  end
end
