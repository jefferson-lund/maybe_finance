class AddHouseholdBudgeting < ActiveRecord::Migration[7.2]
  NEEDS = [ "Loan Payments", "Fees", "Food & Drink", "Healthcare", "Transportation", "Rent & Utilities" ].freeze
  WANTS = [ "Entertainment", "Shopping", "Home Improvement", "Personal Care", "Services", "Gifts & Donations", "Travel" ].freeze

  def up
    add_column :categories, :budget_bucket, :string

    create_table :budget_allocations, id: :uuid do |t|
      t.references :budget, null: false, foreign_key: true, type: :uuid
      t.references :source_category, foreign_key: { to_table: :categories, on_delete: :nullify }, type: :uuid
      t.references :destination_category, foreign_key: { to_table: :categories, on_delete: :nullify }, type: :uuid
      t.references :destination_account, foreign_key: { to_table: :accounts, on_delete: :nullify }, type: :uuid
      t.string :name, null: false
      t.string :basis, null: false
      t.decimal :percentage, precision: 5, scale: 2, null: false
      t.integer :month_offset, null: false, default: 0
      t.boolean :reduces_remaining, null: false, default: true
      t.integer :position, null: false

      t.timestamps
    end

    add_index :budget_allocations, [ :budget_id, :position ], unique: true

    execute <<~SQL.squish
      UPDATE categories
      SET budget_bucket = CASE
        WHEN name IN (#{quoted_names(NEEDS)}) THEN 'needs'
        WHEN name IN (#{quoted_names(WANTS)}) THEN 'wants'
      END
      WHERE classification = 'expense'
    SQL
  end

  def down
    drop_table :budget_allocations
    remove_column :categories, :budget_bucket
  end

  private
    def quoted_names(names)
      names.map { |name| connection.quote(name) }.join(", ")
    end
end
