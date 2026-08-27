require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
  end

  test "budget_date_valid? allows going back 2 years even without entries" do
    two_years_ago = 2.years.ago.beginning_of_month
    assert Budget.budget_date_valid?(two_years_ago, family: @family)
  end

  test "budget_date_valid? allows going back to earliest entry date if more than 2 years ago" do
    # Create an entry 3 years ago
    old_account = Account.create!(
      family: @family,
      accountable: Depository.new,
      name: "Old Account",
      status: "active",
      currency: "USD",
      balance: 1000
    )

    old_entry = Entry.create!(
      account: old_account,
      entryable: Transaction.new(category: categories(:income)),
      date: 3.years.ago,
      name: "Old Transaction",
      amount: 100,
      currency: "USD"
    )

    # Should allow going back to the old entry date
    assert Budget.budget_date_valid?(3.years.ago.beginning_of_month, family: @family)
  end

  test "budget_date_valid? does not allow dates before earliest entry or 2 years ago" do
    # Create an entry 1 year ago
    account = Account.create!(
      family: @family,
      accountable: Depository.new,
      name: "Test Account",
      status: "active",
      currency: "USD",
      balance: 500
    )

    Entry.create!(
      account: account,
      entryable: Transaction.new(category: categories(:income)),
      date: 1.year.ago,
      name: "Recent Transaction",
      amount: 100,
      currency: "USD"
    )

    # Should not allow going back more than 2 years
    refute Budget.budget_date_valid?(3.years.ago.beginning_of_month, family: @family)
  end

  test "budget_date_valid? does not allow future dates beyond current month" do
    refute Budget.budget_date_valid?(2.months.from_now, family: @family)
  end

  test "previous_budget_param returns nil when date is too old" do
    # Create a budget at the oldest allowed date
    two_years_ago = 2.years.ago.beginning_of_month
    budget = Budget.create!(
      family: @family,
      start_date: two_years_ago,
      end_date: two_years_ago.end_of_month,
      currency: "USD"
    )

    assert_nil budget.previous_budget_param
  end

  test "previous_budget_param returns param when date is valid" do
    budget = Budget.create!(
      family: @family,
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      currency: "USD"
    )

    assert_not_nil budget.previous_budget_param
  end

  test "calculates 50 30 20 actuals from categorized transactions" do
    account = @family.accounts.create!(
      name: "Budget checking",
      balance: 0,
      currency: "USD",
      accountable: Depository.new
    )
    income = @family.categories.create!(name: "Pay", classification: "income")
    needs = @family.categories.create!(name: "Housing", budget_bucket: "needs")
    wants = @family.categories.create!(name: "Dining", budget_bucket: "wants")

    create_transaction(account:, date: Date.current, amount: -1000, category: income)
    create_transaction(account:, date: Date.current, amount: 400, category: needs)
    create_transaction(account:, date: Date.current, amount: 200, category: wants)
    create_transaction(account:, date: Date.current, amount: 50)

    budget = Budget.find_or_bootstrap(@family, start_date: Date.current)

    assert_equal 400, budget.needs_spending
    assert_equal 200, budget.wants_spending
    assert_equal 50, budget.unassigned_spending
    assert_equal 350, budget.residual_savings
    assert_in_delta 40, budget.needs_percent
    assert_in_delta 20, budget.wants_percent
    assert_in_delta 35, budget.savings_percent
  end

  test "copies allocation rules from the previous month" do
    previous_budget = Budget.find_or_bootstrap(@family, start_date: 1.month.ago)
    previous_budget.budget_allocations.first.update!(percentage: 12)

    current_budget = Budget.find_or_bootstrap(@family, start_date: Date.current)

    assert_equal previous_budget.budget_allocations.count, current_budget.budget_allocations.count
    assert_equal 12, current_budget.budget_allocations.first.percentage
  end
end
