# frozen_string_literal: true

require 'otel_ruby_goodies/adapters'

module OTelRubyGoodies
  class Railtie < Rails::Railtie
    initializer 'otel_ruby_goodies.configure' do
      OTelRubyGoodies.apply_env_configuration!
    end

    initializer 'otel_ruby_goodies.install_adapters' do
      ActiveSupport.on_load(:active_record) do
        OTelRubyGoodies::Adapters.install!(app_root: Rails.root, config: OTelRubyGoodies.configuration)
      end
    end
  end
end
