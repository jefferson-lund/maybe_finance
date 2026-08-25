require "test_helper"

class PlaidEnvironmentTest < ActiveSupport::TestCase
  setup do
    @config = ActiveSupport::OrderedOptions.new
  end

  test "blank env defaults to sandbox" do
    assert_equal "sandbox", PlaidEnvironment.normalize(nil)
    assert_equal "sandbox", PlaidEnvironment.normalize("  ")
  end

  test "rejects retired development env" do
    error = assert_raises(ArgumentError) { PlaidEnvironment.normalize("development") }
    assert_match(/no longer valid/, error.message)
  end

  test "accepts sandbox and production" do
    assert_equal "sandbox", PlaidEnvironment.normalize("sandbox")
    assert_equal "production", PlaidEnvironment.normalize("PRODUCTION")
  end

  test "rejects unknown environments" do
    error = assert_raises(ArgumentError) { PlaidEnvironment.normalize("staging") }
    assert_match(/Invalid PLAID_ENV/, error.message)
  end

  test "server_index matches Plaid configuration keys" do
    sandbox_index = PlaidEnvironment.server_index("sandbox")
    production_index = PlaidEnvironment.server_index("production")

    assert_equal Plaid::Configuration::Environment.fetch("sandbox"), sandbox_index
    assert_equal Plaid::Configuration::Environment.fetch("production"), production_index
    refute_equal sandbox_index, production_index
  end

  test "apply! disables Plaid when both credentials are blank" do
    with_plaid_env(
      "PLAID_CLIENT_ID" => "",
      "PLAID_SECRET" => "",
      "PLAID_EU_CLIENT_ID" => nil,
      "PLAID_EU_SECRET" => nil
    ) do
      PlaidEnvironment.apply!(@config)
      assert_nil @config.plaid
      assert_nil @config.plaid_eu
    end
  end

  test "apply! fails fast when only the secret is set" do
    with_plaid_env("PLAID_CLIENT_ID" => "", "PLAID_SECRET" => "secret-only") do
      error = assert_raises(ArgumentError) { PlaidEnvironment.apply!(@config) }
      assert_match(/PLAID_CLIENT_ID and PLAID_SECRET/, error.message)
    end
  end

  test "apply! fails fast for a half-configured EU pair" do
    with_plaid_env(
      "PLAID_CLIENT_ID" => nil,
      "PLAID_SECRET" => nil,
      "PLAID_EU_CLIENT_ID" => "eu-id",
      "PLAID_EU_SECRET" => ""
    ) do
      error = assert_raises(ArgumentError) { PlaidEnvironment.apply!(@config) }
      assert_match(/PLAID_EU_CLIENT_ID and PLAID_EU_SECRET/, error.message)
    end
  end

  test "apply! rejects development even when credentials are omitted" do
    with_plaid_env(
      "PLAID_CLIENT_ID" => nil,
      "PLAID_SECRET" => nil,
      "PLAID_ENV" => "development"
    ) do
      error = assert_raises(ArgumentError) { PlaidEnvironment.apply!(@config) }
      assert_match(/no longer valid/, error.message)
    end
  end

  test "apply! configures US client from a complete credential pair" do
    with_plaid_env(
      "PLAID_CLIENT_ID" => " client-id ",
      "PLAID_SECRET" => " secret ",
      "PLAID_ENV" => "sandbox",
      "PLAID_EU_CLIENT_ID" => nil,
      "PLAID_EU_SECRET" => nil
    ) do
      PlaidEnvironment.apply!(@config)

      assert_equal PlaidEnvironment.server_index("sandbox"), @config.plaid.server_index
      assert_equal "client-id", @config.plaid.api_key["PLAID-CLIENT-ID"]
      assert_equal "secret", @config.plaid.api_key["PLAID-SECRET"]
      assert_nil @config.plaid_eu
    end
  end

  test "apply! requires valid APP_DOMAIN for configured production Plaid" do
    with_plaid_env(
      "PLAID_CLIENT_ID" => "client-id",
      "PLAID_SECRET" => "secret",
      "PLAID_ENV" => "production",
      "APP_DOMAIN" => ""
    ) do
      error = assert_raises(ArgumentError) do
        PlaidEnvironment.apply!(@config, require_app_domain: true)
      end

      assert_match(/Invalid APP_DOMAIN/, error.message)
    end
  end

  test "apply! rejects localhost APP_DOMAIN for Plaid production" do
    with_plaid_env(
      "PLAID_CLIENT_ID" => "client-id",
      "PLAID_SECRET" => "secret",
      "PLAID_ENV" => "production",
      "APP_DOMAIN" => "localhost:3000"
    ) do
      error = assert_raises(ArgumentError) do
        PlaidEnvironment.apply!(@config, require_app_domain: true)
      end

      assert_match(/requires a public APP_DOMAIN/, error.message)
    end
  end

  private
    def with_plaid_env(overrides)
      keys = %w[PLAID_CLIENT_ID PLAID_SECRET PLAID_EU_CLIENT_ID PLAID_EU_SECRET PLAID_ENV APP_DOMAIN]
      previous = keys.index_with { |key| ENV[key] }

      keys.each { |key| ENV.delete(key) }
      overrides.each do |key, value|
        if value.nil?
          ENV.delete(key)
        else
          ENV[key] = value
        end
      end

      yield
    ensure
      keys.each do |key|
        if previous[key].nil?
          ENV.delete(key)
        else
          ENV[key] = previous[key]
        end
      end
    end
end
