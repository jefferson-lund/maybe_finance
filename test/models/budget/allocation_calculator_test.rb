require "test_helper"

class Budget::AllocationCalculatorTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @budget = Budget.find_or_bootstrap(@family, start_date: Date.current)
    @budget.update!(expected_income: 1000, budgeted_spending: 600)
  end

  test "uses workbook waterfall without subtracting next month tithing" do
    rows = @budget.allocation_rows.index_by { |row| row.allocation.name }

    assert_equal 100, rows.fetch("Next Month's Tithing").target
    assert_equal 100, rows.fetch("LTS").target
    assert_equal 150, rows.fetch("Individual Fun Money 1").target
    assert_equal 150, rows.fetch("Individual Fun Money 2").target
  end

  test "marks unmapped destinations as needing setup" do
    allocation = @budget.budget_allocations.find_by!(name: "LTS")

    assert_not allocation.destination_configured?
    assert_equal "Needs setup", allocation.destination_name
  end

  test "tracks Schwab transfers against eligible company payroll income only" do
    company_payroll = @family.categories.create!(
      name: "Company Payroll", color: "#6471eb", lucide_icon: "briefcase-business", classification: "income"
    )
    employer_payroll = @family.categories.create!(
      name: "Employer Payroll", color: "#6471eb", lucide_icon: "briefcase-business",
      classification: "income", parent: company_payroll
    )
    excluded_income = @family.categories.create!(
      name: "Monterey Credit Union and DFAS", color: "#6471eb", lucide_icon: "landmark",
      classification: "income"
    )
    checking = @family.accounts.create!(
      accountable: Depository.new, name: "Checking", balance: 0, currency: "USD", status: "active"
    )
    schwab_ira = @family.accounts.create!(
      accountable: Investment.new, name: "Charles Schwab IRA", balance: 0, currency: "USD", status: "active"
    )

    create_transaction(account: checking, amount: -5000, category: employer_payroll)
    create_transaction(account: checking, amount: -3000, category: excluded_income)
    create_transaction(account: schwab_ira, amount: -450, kind: "funds_movement")

    allocation = @budget.budget_allocations.find_by!(name: "Schwab IRA")
    allocation.update!(source_category: company_payroll, destination_account: schwab_ira)
    row = @budget.allocation_rows.index_by { |result| result.allocation.name }.fetch("Schwab IRA")

    assert_equal 500, row.target
    assert_equal 450, row.actual
    assert_equal "Company Payroll income", allocation.basis_name
  end
end
