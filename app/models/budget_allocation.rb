class BudgetAllocation < ApplicationRecord
  belongs_to :budget
  belongs_to :source_category, class_name: "Category", optional: true
  belongs_to :destination_category, class_name: "Category", optional: true
  belongs_to :destination_account, class_name: "Account", optional: true

  enum :basis, {
    gross_income: "gross_income",
    selected_income: "selected_income",
    remaining_cash: "remaining_cash"
  }, validate: true

  validates :name, :percentage, :position, presence: true
  validates :position, uniqueness: { scope: :budget_id }
  validates :percentage, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validates :month_offset, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 12 }
  validate :single_destination
  validate :categories_and_accounts_belong_to_family

  scope :ordered, -> { order(:position) }

  def destination_name
    destination_category&.name || destination_account&.name || "Needs setup"
  end

  def destination_configured?
    destination_category.present? || destination_account.present?
  end

  def basis_name
    case basis
    when "gross_income"
      "all income"
    when "selected_income"
      source_category ? "#{source_category.name} income" : "selected income"
    when "remaining_cash"
      "remaining cash"
    end
  end

  private
    def single_destination
      if destination_category.present? && destination_account.present?
        errors.add(:base, "Choose either a destination category or account")
      end
    end

    def categories_and_accounts_belong_to_family
      family = budget&.family
      return unless family

      errors.add(:source_category, "must belong to this family") if source_category && source_category.family_id != family.id
      errors.add(:destination_category, "must belong to this family") if destination_category && destination_category.family_id != family.id
      errors.add(:destination_account, "must belong to this family") if destination_account && destination_account.family_id != family.id
    end
end
