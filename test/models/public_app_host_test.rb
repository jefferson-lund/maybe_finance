require "test_helper"
require "ostruct"
require Rails.root.join("lib/maybe_boot/public_app_host")

class PublicAppHostTest < ActiveSupport::TestCase
  test "parses host from a bare domain" do
    assert_equal "maybe.aj-data.com", PublicAppHost.parse("maybe.aj-data.com")
  end

  test "normalizes host case and preserves an explicit port" do
    assert_equal "maybe.example.com:443", PublicAppHost.parse("Maybe.Example.com:443")
  end

  test "rejects blank and malformed values" do
    assert_nil PublicAppHost.parse(nil)
    assert_nil PublicAppHost.parse("  ")
    assert_nil PublicAppHost.parse("not a host")
    assert_nil PublicAppHost.parse("example.com:abc")
    assert_nil PublicAppHost.parse("https://example.com")
    assert_nil PublicAppHost.parse("example.com/path")
    assert_nil PublicAppHost.parse("example.com?query")
    assert_nil PublicAppHost.parse("example.com:0")
  end

  test "builds canonical HTTPS Action Cable origin for a public host" do
    assert_equal(
      [ "https://maybe.example.com" ],
      PublicAppHost.action_cable_origins("maybe.example.com", ssl: true)
    )
  end

  test "keeps non-default ports on public origins" do
    assert_equal "maybe.example.com:3000", PublicAppHost.parse("maybe.example.com:3000")
    assert_equal(
      [ "https://maybe.example.com:3000" ],
      PublicAppHost.action_cable_origins("maybe.example.com:3000", ssl: true)
    )
  end

  test "builds canonical HTTP Action Cable origin for localhost" do
    assert_equal(
      [ "http://localhost:3000" ],
      PublicAppHost.action_cable_origins("localhost:3000", ssl: false)
    )
  end

  test "omits the default port for each canonical scheme" do
    assert_equal(
      [ "https://maybe.example.com" ],
      PublicAppHost.action_cable_origins("maybe.example.com:443", ssl: true)
    )
    assert_equal(
      [ "http://localhost" ],
      PublicAppHost.action_cable_origins("localhost:80", ssl: false)
    )
  end

  test "builds a loopback HTTP origin and handles blank configuration" do
    assert_equal(
      [ "http://127.0.0.1:3000" ],
      PublicAppHost.action_cable_origins("127.0.0.1:3000", ssl: false)
    )
    assert_equal [], PublicAppHost.action_cable_origins(nil, ssl: false)
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

  test "omits canonical default ports from URL options" do
    assert_equal(
      { host: "maybe.example.com", protocol: "https", port: nil },
      PublicAppHost.url_options("maybe.example.com:443")
    )
    assert_equal(
      { host: "localhost", protocol: "http", port: nil },
      PublicAppHost.url_options("localhost:80")
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

  test "leaves legacy self-hosted Host Authorization open when APP_DOMAIN is blank" do
    config = ActiveSupport::OrderedOptions.new
    config.app_mode = "self_hosted".inquiry

    PublicAppHost.configure_host_authorization!(config, nil)

    assert_nil config.hosts
    assert_nil config.host_authorization
  end

  test "configures canonical Action Cable policy for self-hosted production" do
    config = app_config("self_hosted")

    PublicAppHost.configure_action_cable!(config, "maybe.example.com", ssl: true)

    assert_equal [ "https://maybe.example.com" ], config.action_cable.allowed_request_origins
    assert_equal false, config.action_cable.allow_same_origin_as_host
  end

  test "leaves managed Action Cable policy unchanged" do
    config = app_config("managed")
    config.action_cable.allowed_request_origins = [ "https://managed.example.com" ]
    config.action_cable.allow_same_origin_as_host = true

    PublicAppHost.configure_action_cable!(config, nil, ssl: true)

    assert_equal [ "https://managed.example.com" ], config.action_cable.allowed_request_origins
    assert_equal true, config.action_cable.allow_same_origin_as_host
  end

  test "configures HTTP Action Cable origin for a LAN deployment without SSL" do
    config = app_config("self_hosted")

    PublicAppHost.configure_action_cable!(config, "192.168.1.10:3000", ssl: false)

    assert_equal [ "http://192.168.1.10:3000" ], config.action_cable.allowed_request_origins
    assert_equal false, config.action_cable.allow_same_origin_as_host
  end

  test "selects HTTPS for public hosts even when proxy SSL flags are off" do
    assert PublicAppHost.action_cable_ssl?(
      "maybe.example.com",
      ssl_configured: false
    )
  end

  test "allows HTTP for private network hosts when proxy SSL flags are off" do
    refute PublicAppHost.action_cable_ssl?("192.168.1.10:3000", ssl_configured: false)
    refute PublicAppHost.action_cable_ssl?("maybe.local:3000", ssl_configured: false)
    refute PublicAppHost.action_cable_ssl?("maybe-server:3000", ssl_configured: false)
  end

  test "selects HTTPS for private network hosts when SSL is configured" do
    assert PublicAppHost.action_cable_ssl?("192.168.1.10:3000", ssl_configured: true)
  end

  test "leaves legacy self-hosted Action Cable policy unchanged when APP_DOMAIN is blank" do
    config = app_config("self_hosted")

    PublicAppHost.configure_action_cable!(config, nil, ssl: false)

    assert_nil config.action_cable.allowed_request_origins
    assert_nil config.action_cable.allow_same_origin_as_host
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

  test "Action Cable accepts only canonical public HTTPS origin" do
    assert cable_allows?(
      domain: "maybe.example.com",
      request_url: "https://maybe.example.com/cable",
      origin: "https://maybe.example.com"
    )
    refute cable_allows?(
      domain: "maybe.example.com",
      request_url: "http://maybe.example.com/cable",
      origin: "http://maybe.example.com"
    )
    refute cable_allows?(
      domain: "maybe.example.com",
      request_url: "https://maybe.example.com/cable",
      origin: "https://evil.example"
    )
    refute cable_allows?(
      domain: "maybe.example.com",
      request_url: "https://maybe.example.com/cable",
      origin: nil
    )
  end

  test "Action Cable accepts only canonical localhost HTTP origin" do
    assert cable_allows?(
      domain: "localhost:3000",
      request_url: "http://localhost:3000/cable",
      origin: "http://localhost:3000"
    )
    refute cable_allows?(
      domain: "localhost:3000",
      request_url: "https://localhost:3000/cable",
      origin: "https://localhost:3000"
    )
  end

  test "Action Cable accepts tunneled HTTPS origin over internal HTTP" do
    assert cable_allows?(
      domain: "maybe.example.com",
      request_url: "http://maybe.example.com/cable",
      origin: "https://maybe.example.com",
      headers: { "HTTP_X_FORWARDED_PROTO" => "https" }
    )
    refute cable_allows?(
      domain: "maybe.example.com",
      request_url: "http://maybe.example.com/cable",
      origin: "http://maybe.example.com",
      headers: { "HTTP_X_FORWARDED_PROTO" => "https" }
    )
  end

  test "Action Cable rejects a public Origin that omits configured non-default port" do
    refute cable_allows?(
      domain: "maybe.example.com:3000",
      request_url: "http://maybe.example.com/cable",
      origin: "https://maybe.example.com"
    )
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

    def app_config(mode, action_cable: ActiveSupport::OrderedOptions.new)
      ActiveSupport::OrderedOptions.new.tap do |config|
        config.app_mode = mode.inquiry
        config.action_cable = action_cable
      end
    end

    def cable_allows?(domain:, request_url:, origin:, headers: {})
      server = ActionCable::Server::Base.new
      config = app_config("self_hosted", action_cable: server.config)
      PublicAppHost.configure_action_cable!(
        config,
        domain,
        ssl: PublicAppHost.action_cable_ssl?(domain, ssl_configured: false)
      )

      env = Rack::MockRequest.env_for(
        request_url,
        headers.merge("HTTP_ORIGIN" => origin)
      )
      ApplicationCable::Connection.new(server, env).send(:allow_request_origin?)
    end
end
