require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "index redirects to the complete previous calendar month" do
    travel_to Date.new(2026, 8, 27) do
      get budgets_url

      budget = @user.family.budgets.find_by!(start_date: Date.new(2026, 7, 1))
      assert_equal Date.new(2026, 7, 31), budget.end_date
      assert_redirected_to budget_url(budget)
    end
  end

  test "index crosses the year boundary" do
    travel_to Date.new(2026, 1, 10) do
      get budgets_url

      assert_redirected_to budget_url("dec-2025")
    end
  end

  test "show renders the household budget dashboard" do
    budget = Budget.find_or_bootstrap(@user.family, start_date: Date.current)

    get budget_url(budget)

    assert_response :success
    assert_select "h2", text: "50 / 30 / 20"
    assert_select "h2", text: "Household allocation waterfall"
  end

  test "edit renders configurable allocation rules" do
    budget = Budget.find_or_bootstrap(@user.family, start_date: Date.current)

    get edit_budget_url(budget)

    assert_response :success
    assert_select "h2", text: "Household allocation rules"
    assert_select "form", minimum: 6
  end
end
