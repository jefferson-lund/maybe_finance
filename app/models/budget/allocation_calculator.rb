class Budget::AllocationCalculator
  Row = Data.define(:allocation, :target, :actual) do
    def variance
      actual - target
    end
  end

  def initialize(budget)
    @budget = budget
  end

  def rows
    remaining_target = expected_income - budgeted_spending - reducing_fixed_target

    budget.budget_allocations.ordered.map do |allocation|
      Row.new(
        allocation: allocation,
        target: target_for(allocation, remaining_target:),
        actual: actual_for(allocation)
      )
    end
  end

  private
    attr_reader :budget

    def expected_income
      budget.expected_income || 0
    end

    def budgeted_spending
      budget.budgeted_spending || 0
    end

    def reducing_fixed_target
      budget.budget_allocations.reject(&:remaining_cash?).select(&:reduces_remaining?).sum do |allocation|
        target_for(allocation, remaining_target: 0)
      end
    end

    def target_for(allocation, remaining_target:)
      basis = case allocation.basis
      when "gross_income"
        expected_income
      when "selected_income"
        selected_income_for(allocation)
      when "remaining_cash"
        remaining_target
      end

      basis * allocation.percentage / 100
    end

    def selected_income_for(allocation)
      return 0 unless allocation.source_category

      transaction_total(
        period: budget.period,
        category: allocation.source_category,
        direction: :income
      )
    end

    def actual_for(allocation)
      period = shifted_period(allocation.month_offset)

      if allocation.destination_category
        transaction_total(period:, category: allocation.destination_category, direction: :expense)
      elsif allocation.destination_account
        transfer_total(period:, account: allocation.destination_account)
      else
        0
      end
    end

    def shifted_period(month_offset)
      start_date = budget.start_date.advance(months: month_offset)
      Period.custom(start_date:, end_date: start_date.end_of_month)
    end

    def transaction_total(period:, category:, direction:)
      category_ids = [ category.id, *category.subcategory_ids ]
      scope = budget.family.transactions.visible.in_period(period)
                    .where(category_id: category_ids)
                    .where.not(kind: %w[funds_movement one_time cc_payment])
                    .includes(:entry)

      scope.sum do |transaction|
        amount = transaction.entry.amount
        next 0 unless direction == :income ? amount.negative? : amount.positive?

        converted_amount(transaction.entry).abs
      end
    end

    def transfer_total(period:, account:)
      account.transactions.funds_movement.in_period(period).includes(:entry).sum do |transaction|
        next 0 unless transaction.entry.amount.negative?

        converted_amount(transaction.entry).abs
      end
    end

    def converted_amount(entry)
      entry.amount_money.exchange_to(
        budget.family.currency,
        date: entry.date,
        fallback_rate: 1
      ).amount
    end
end
