require "test_helper"
require Rails.root.join("lib/maybe_boot/public_app_host")

class PublicAppHostTest < ActiveSupport::TestCase
  test "parses host from a bare domain" do
    assert_equal "maybe.aj-data.com", PublicAppHost.parse("maybe.aj-data.com")
  end

  test "strips scheme path and port" do
    assert_equal "maybe.example.com", PublicAppHost.parse("https://Maybe.Example.com:443/path")
  end

  test "rejects blank and malformed values" do
    assert_nil PublicAppHost.parse(nil)
    assert_nil PublicAppHost.parse("  ")
    assert_nil PublicAppHost.parse("not a host")
    assert_nil PublicAppHost.parse("https://example.com:abc")
  end

  test "builds http and https Action Cable origins" do
    assert_equal (
      [ "https://maybe.example.com", "http://maybe.example.com" ]
    ), PublicAppHost.action_cable_origins("maybe.example.com")
  end

  test "keeps non-default ports on origins" do
    assert_equal "maybe.example.com:3000", PublicAppHost.parse("http://maybe.example.com:3000")
    assert_equal (
      [ "https://maybe.example.com:3000", "http://maybe.example.com:3000" ]
    ), PublicAppHost.action_cable_origins("maybe.example.com:3000")
  end

  test "rejects userinfo and IPv6 literals" do
    assert_nil PublicAppHost.parse("https://alice:secret@maybe.example.com")
    assert_nil PublicAppHost.parse("2001:db8::1")
  end
end
