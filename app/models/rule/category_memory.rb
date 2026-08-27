class Rule::CategoryMemory
  class << self
    def remember!(transaction)
      return unless transaction.saved_change_to_category_id?
      return unless transaction.category && transaction.merchant

      family = transaction.entry.account.family

      Rule.transaction do
        family.lock!
        rule = find_existing_rule(family, transaction.merchant_id) || family.rules.build(
          resource_type: "transaction",
          active: true
        )

        rule.name = "Remember #{transaction.merchant.name} as #{transaction.category.name}"
        rule.active = true

        if rule.new_record?
          rule.conditions.build(
            condition_type: "transaction_merchant",
            operator: "=",
            value: transaction.merchant_id
          )
          rule.actions.build(
            action_type: "set_transaction_category",
            value: transaction.category_id
          )
        else
          rule.actions.first.value = transaction.category_id
        end

        rule.save!
        rule
      end
    end

    private
      def find_existing_rule(family, merchant_id)
        family.rules.includes(:conditions, :actions).find do |rule|
          rule.conditions.one? &&
            rule.actions.one? &&
            rule.conditions.first.attributes.slice("condition_type", "operator", "value") == {
              "condition_type" => "transaction_merchant",
              "operator" => "=",
              "value" => merchant_id
            } &&
            rule.actions.first.action_type == "set_transaction_category"
        end
      end
  end
end
