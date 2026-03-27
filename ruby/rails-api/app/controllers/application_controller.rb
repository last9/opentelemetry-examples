class ApplicationController < ActionController::API
  TEAM_MAP = {
    'payment'  => 'billing',
    'auth'     => 'identity',
    'users'    => 'identity',
    'internal' => 'platform',
    'public'   => 'platform',
    'checkout' => 'billing'
  }.freeze

  before_action :set_team_context

  private

  def set_team_context
    CurrentRequest.team = TEAM_MAP[controller_name]
  end
end
