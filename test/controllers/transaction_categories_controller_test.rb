require "test_helper"

class TransactionCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @entry = entries(:transaction)
  end

  test "automatically remembers a merchant category reassignment" do
    category = categories(:subcategory)

    assert_difference "Rule.count", 1 do
      patch transaction_category_url(@entry), params: {
        entry: {
          entryable_type: "Transaction",
          entryable_attributes: {
            id: @entry.transaction.id,
            category_id: category.id
          }
        }
      }
    end

    rule = @entry.account.family.rules.order(:created_at).last
    assert rule.active?
    assert_equal @entry.transaction.merchant_id, rule.conditions.first.value
    assert_equal category.id, rule.actions.first.value
  end
end
