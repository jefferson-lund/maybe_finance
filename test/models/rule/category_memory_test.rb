require "test_helper"

class Rule::CategoryMemoryTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(
      name: "Category memory",
      balance: 0,
      currency: "USD",
      accountable: Depository.new
    )
    @merchant = @family.merchants.create!(name: "Market", type: "FamilyMerchant")
    @groceries = @family.categories.create!(name: "Groceries")
    @dining = @family.categories.create!(name: "Dining")
    @entry = create_transaction(account: @account, merchant: @merchant)
  end

  test "creates an active merchant category rule" do
    @entry.transaction.update!(category: @groceries)

    assert_difference "@family.rules.count", 1 do
      Rule::CategoryMemory.remember!(@entry.transaction)
    end

    rule = @family.rules.last
    assert rule.active?
    assert_equal "transaction_merchant", rule.conditions.first.condition_type
    assert_equal @merchant.id, rule.conditions.first.value
    assert_equal "set_transaction_category", rule.actions.first.action_type
    assert_equal @groceries.id, rule.actions.first.value
  end

  test "updates the remembered category without creating a duplicate rule" do
    @entry.transaction.update!(category: @groceries)
    rule = Rule::CategoryMemory.remember!(@entry.transaction)

    @entry.transaction.update!(category: @dining)

    assert_no_difference "@family.rules.count" do
      assert_equal rule, Rule::CategoryMemory.remember!(@entry.transaction)
    end

    assert_equal @dining.id, rule.reload.actions.first.value
  end

  test "does not guess a memory rule without a merchant" do
    entry = create_transaction(account: @account)
    entry.transaction.update!(category: @groceries)

    assert_no_difference "@family.rules.count" do
      assert_nil Rule::CategoryMemory.remember!(entry.transaction)
    end
  end
end
