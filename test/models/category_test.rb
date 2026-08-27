require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  def setup
    @family = families(:dylan_family)
  end

  test "replacing and destroying" do
    transactions = categories(:food_and_drink).transactions.to_a

    categories(:food_and_drink).replace_and_destroy!(categories(:income))

    assert_equal categories(:income), transactions.map { |t| t.reload.category }.uniq.first
  end

  test "replacing with nil should nullify the category" do
    transactions = categories(:food_and_drink).transactions.to_a

    categories(:food_and_drink).replace_and_destroy!(nil)

    assert_nil transactions.map { |t| t.reload.category }.uniq.first
  end

  test "subcategory can only be one level deep" do
    category = categories(:subcategory)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      category.subcategories.create!(name: "Invalid category", family: @family)
    end

    assert_equal "Validation failed: Parent can't have more than 2 levels of subcategories", error.message
  end

  test "subcategory inherits or overrides its parent budget bucket" do
    parent = @family.categories.create!(name: "Food", budget_bucket: "needs")
    child = @family.categories.create!(name: "Meals out", parent:)

    assert_equal "needs", child.effective_budget_bucket

    child.update!(budget_bucket: "wants")
    assert_equal "wants", child.effective_budget_bucket
  end

  test "income category cannot have an expense budget bucket" do
    category = @family.categories.new(name: "Paycheck", classification: "income", budget_bucket: "needs")

    assert_not category.valid?
    assert_includes category.errors[:budget_bucket], "is only available for expense categories"
  end
end
