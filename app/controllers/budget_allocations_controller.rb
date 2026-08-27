class BudgetAllocationsController < ApplicationController
  def update
    budget = Current.family.budgets.find_by!(start_date: Budget.param_to_date(params[:budget_month_year]))
    allocation = budget.budget_allocations.find(params[:id])

    if allocation.update(budget_allocation_params)
      redirect_to edit_budget_path(budget, anchor: "allocation-rules"), notice: "Allocation updated"
    else
      redirect_to edit_budget_path(budget, anchor: "allocation-rules"), alert: allocation.errors.full_messages.to_sentence
    end
  end

  private
    def budget_allocation_params
      params.require(:budget_allocation).permit(
        :name, :basis, :percentage, :source_category_id, :destination_category_id,
        :destination_account_id, :month_offset, :reduces_remaining
      )
    end
end
