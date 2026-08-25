require "test_helper"
require "ostruct"

class PlaidItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "new uses APP_DOMAIN for Plaid redirect despite a different request host" do
    Rails.env.stubs(:production?).returns(true)
    Family.any_instance.expects(:get_link_token).with(
      webhooks_url: "https://maybe.example.com/webhooks/plaid",
      redirect_url: "https://maybe.example.com/accounts",
      accountable_type: "Depository",
      region: :us
    ).returns("test-link-token")

    with_env_overrides("APP_DOMAIN" => "maybe.example.com") do
      host! "evil.example:8443"
      sign_in @user
      get new_plaid_item_path
    end

    assert_response :success
  end

  test "new uses APP_DOMAIN for EU Plaid webhook" do
    Rails.env.stubs(:production?).returns(true)
    Family.any_instance.expects(:get_link_token).with(
      webhooks_url: "https://maybe.example.com/webhooks/plaid_eu",
      redirect_url: "https://maybe.example.com/accounts",
      accountable_type: "Depository",
      region: :eu
    ).returns("test-link-token")

    with_env_overrides("APP_DOMAIN" => "maybe.example.com") do
      host! "evil.example"
      sign_in @user
      get new_plaid_item_path(region: "eu")
    end

    assert_response :success
  end

  test "edit uses APP_DOMAIN for update Link token" do
    Rails.env.stubs(:production?).returns(true)
    PlaidItem.any_instance.expects(:get_update_link_token).with(
      webhooks_url: "https://maybe.example.com/webhooks/plaid",
      redirect_url: "https://maybe.example.com/accounts"
    ).returns("test-link-token")

    with_env_overrides("APP_DOMAIN" => "maybe.example.com") do
      host! "evil.example"
      sign_in @user
      get edit_plaid_item_path(plaid_items(:one))
    end

    assert_response :success
  end

  test "new preserves HTTP and port for localhost Sandbox" do
    Family.any_instance.expects(:get_link_token).with(
      webhooks_url: "http://evil.example/webhooks/plaid",
      redirect_url: "http://localhost:3000/accounts",
      accountable_type: "Depository",
      region: :us
    ).returns("test-link-token")

    with_env_overrides("APP_DOMAIN" => "localhost:3000") do
      host! "evil.example"
      sign_in @user
      get new_plaid_item_path
    end

    assert_response :success
  end

  test "create" do
    @plaid_provider = mock
    Provider::Registry.expects(:plaid_provider_for_region).with("us").returns(@plaid_provider)

    public_token = "public-sandbox-1234"

    @plaid_provider.expects(:exchange_public_token).with(public_token).returns(
      OpenStruct.new(access_token: "access-sandbox-1234", item_id: "item-sandbox-1234")
    )

    assert_difference "PlaidItem.count", 1 do
      post plaid_items_url, params: {
        plaid_item: {
          public_token: public_token,
          region: "us",
          metadata: { institution: { name: "Plaid Item Name" } }
        }
      }
    end

    assert_equal "Account linked successfully.  Please wait for accounts to sync.", flash[:notice]
    assert_redirected_to accounts_path
  end

  test "destroy" do
    delete plaid_item_url(plaid_items(:one))

    assert_equal "Accounts scheduled for deletion.", flash[:notice]
    assert_enqueued_with job: DestroyJob
    assert_redirected_to accounts_path
  end

  test "sync" do
    plaid_item = plaid_items(:one)
    PlaidItem.any_instance.expects(:sync_later).once

    post sync_plaid_item_url(plaid_item)

    assert_redirected_to accounts_path
  end
end
