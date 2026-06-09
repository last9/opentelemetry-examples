# frozen_string_literal: true

require "test_helper"

# Guards the POST /api/v1/public/echo route, whose action (echo_post) must exist.
# The route previously pointed at a missing action, returning 404.
class PublicEchoTest < ActionDispatch::IntegrationTest
  test "POST echo returns 200 and echoes the raw request body" do
    post "/api/v1/public/echo",
         params:  '{"id":42}',
         headers: { "Content-Type" => "application/json" }

    assert_equal 200, response.status
    assert_equal '{"id":42}', JSON.parse(response.body)["echo"]
  end

  test "GET echo still returns params (unchanged)" do
    get "/api/v1/public/echo", params: { hello: "world" }

    assert_equal 200, response.status
    assert_equal "world", JSON.parse(response.body)["params"]["hello"]
  end
end
