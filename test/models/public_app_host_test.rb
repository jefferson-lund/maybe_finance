require "test_helper"
require "ostruct"
require Rails.root.join("lib/maybe_boot/public_app_host")

class PublicAppHostTest < ActiveSupport::TestCase
  test "parses host from a bare domain" do
    assert_equal "maybe.aj-data.com", PublicAppHost.parse("maybe.aj-data.com")
  end

  test "normalizes case and a default port" do
    assert_equal "maybe.example.com", PublicAppHost.parse("Maybe.Example.com:443")
  end

  test "rejects blank and malformed values" do
    assert_nil PublicAppHost.parse(nil)
    assert_nil PublicAppHost.parse("  ")
    assert_nil PublicAppHost.parse("not a host")
    assert_nil PublicAppHost.parse("example.com:abc")
    assert_nil PublicAppHost.parse("https://example.com")
    assert_nil PublicAppHost.parse("example.com/path")
    assert_nil PublicAppHost.parse("example.com?query")
  end

  test "builds http and https Action Cable origins" do
    assert_equal (
      [ "https://maybe.example.com", "http://maybe.example.com" ]
    ), PublicAppHost.action_cable_origins("maybe.example.com")
  end

  test "keeps non-default ports on origins" do
    assert_equal "maybe.example.com:3000", PublicAppHost.parse("maybe.example.com:3000")
    assert_equal (
      [ "https://maybe.example.com:3000", "http://maybe.example.com:3000" ]
    ), PublicAppHost.action_cable_origins("maybe.example.com:3000")
  end

  test "rejects userinfo and IPv6 literals" do
    assert_nil PublicAppHost.parse("alice:secret@maybe.example.com")
    assert_nil PublicAppHost.parse("2001:db8::1")
  end

  test "parse! raises for malformed APP_DOMAIN" do
    error = assert_raises(ArgumentError) { PublicAppHost.parse!("not a host") }

    assert_match(/Invalid APP_DOMAIN/, error.message)
  end

  test "builds canonical HTTPS URL options for public hosts" do
    assert_equal(
      { host: "maybe.example.com", protocol: "https", port: nil },
      PublicAppHost.url_options("maybe.example.com")
    )
  end

  test "keeps fallback protocol for localhost" do
    assert_equal(
      { host: "localhost", protocol: "http", port: 3000 },
      PublicAppHost.url_options("localhost:3000")
    )
  end

  test "returns empty URL options when APP_DOMAIN is blank" do
    assert_equal({}, PublicAppHost.url_options(nil))
  end

  test "builds production host allowlist without the configured port" do
    assert_equal(
      [ "maybe.example.com" ],
      PublicAppHost.allowed_hosts("maybe.example.com:3000")
    )
  end

  test "allows only a configured loopback host" do
    assert_equal [ "localhost" ], PublicAppHost.allowed_hosts("localhost:3000")
  end

  test "returns no host allowlist when APP_DOMAIN is blank" do
    assert_equal [], PublicAppHost.allowed_hosts(nil)
  end

  test "configures Host Authorization for self-hosted production" do
    config = ActiveSupport::OrderedOptions.new
    config.app_mode = "self_hosted".inquiry

    PublicAppHost.configure_host_authorization!(config, "maybe.example.com:3000")

    assert_equal [ "maybe.example.com" ], config.hosts
    assert config.host_authorization[:exclude].call(OpenStruct.new(path: "/up"))
    refute config.host_authorization[:exclude].call(OpenStruct.new(path: "/"))
  end

  test "leaves managed Host Authorization unchanged" do
    config = ActiveSupport::OrderedOptions.new
    config.app_mode = "managed".inquiry
    config.hosts = [ "managed.example.com" ]

    PublicAppHost.configure_host_authorization!(config, nil)

    assert_equal [ "managed.example.com" ], config.hosts
    assert_nil config.host_authorization
  end

  test "Host Authorization accepts only the configured hostname" do
    request = Rack::MockRequest.new(host_authorization)

    assert_equal 200, request.get("/", "HTTP_HOST" => "maybe.example.com:8443").status
    assert_equal 403, request.get("/", "HTTP_HOST" => "evil.example").status
    assert_equal 403, request.get("/", "HTTP_HOST" => "sub.maybe.example.com").status
  end

  test "Host Authorization rejects a hostile forwarded host" do
    response = Rack::MockRequest.new(host_authorization).get(
      "/",
      "HTTP_HOST" => "maybe.example.com",
      "HTTP_X_FORWARDED_HOST" => "evil.example"
    )

    assert_equal 403, response.status
  end

  test "Host Authorization excludes only the health endpoint" do
    request = Rack::MockRequest.new(host_authorization)

    assert_equal 200, request.get("/up", "HTTP_HOST" => "127.0.0.1").status
    assert_equal 403, request.get("/", "HTTP_HOST" => "127.0.0.1").status
  end

  private
    def host_authorization
      app = ->(_env) { [ 200, { "content-type" => "text/plain" }, [ "ok" ] ] }
      ActionDispatch::HostAuthorization.new(
        app,
        PublicAppHost.allowed_hosts("maybe.example.com:3000"),
        exclude: PublicAppHost.method(:health_check_request?)
      )
    end
end
