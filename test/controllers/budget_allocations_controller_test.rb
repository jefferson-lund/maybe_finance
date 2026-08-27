require "test_helper"

class BudgetAllocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @budget = Budget.find_or_bootstrap(@user.family, start_date: Date.current)
    @allocation = @budget.budget_allocations.find_by!(name: "LTS")
  end

  test "updates an allocation rule" do
    patch budget_budget_allocation_url(@budget, @allocation), params: {
      budget_allocation: {
        name: "Long-term savings",
        basis: "gross_income",
        percentage: 15,
        month_offset: 0,
        reduces_remaining: true
      }
    }

    assert_redirected_to edit_budget_url(@budget, anchor: "allocation-rules")
    assert_equal "Long-term savings", @allocation.reload.name
    assert_equal 15, @allocation.percentage
  end
end
