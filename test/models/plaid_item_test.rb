require "test_helper"
require "ostruct"

class PlaidItemTest < ActiveSupport::TestCase
  include SyncableInterfaceTest

  setup do
    @plaid_item = @syncable = plaid_items(:one)
    @plaid_provider = mock
    Provider::Registry.stubs(:plaid_provider_for_region).returns(@plaid_provider)
  end

  test "removes plaid item when destroyed" do
    @plaid_provider.expects(:remove_item).with(@plaid_item.access_token).once

    assert_difference "PlaidItem.count", -1 do
      @plaid_item.destroy
    end
  end

  test "stores the institution logo returned by Plaid" do
    logo_data = "plaid institution logo"
    institution = OpenStruct.new(
      institution_id: "ins_logo",
      url: "https://example.com",
      primary_color: "#ffffff",
      logo: Base64.strict_encode64(logo_data)
    )

    @plaid_item.upsert_plaid_institution_snapshot!(institution)

    assert @plaid_item.logo.attached?
    assert_equal logo_data, @plaid_item.logo.download
  end
end
