require "test_helper"

class Provider::RegistryTest < ActiveSupport::TestCase
  test "raises for an unknown provider" do
    error = assert_raises Provider::Registry::Error do
      Provider::Registry.get_provider(:unknown)
    end

    assert_equal "Provider 'unknown' not found in registry", error.message
  end
end
