class CreateBillingCatalogue < ActiveRecord::Migration[8.1]
  def change
    create_table :billable_metrics do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :code, null: false
      t.string :name, null: false
      t.string :description
      t.string :aggregation_type, null: false
      t.string :property_name
      t.jsonb :filters, null: false, default: {}
      t.timestamps
    end
    add_index :billable_metrics, [ :organization_id, :code ], unique: true

    create_table :plans do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :code, null: false
      t.string :name, null: false
      t.string :description
      t.string :currency, null: false, default: "GBP"
      t.string :interval, null: false, default: "monthly"
      t.bigint :base_amount_cents, null: false, default: 0
      t.bigint :minimum_amount_cents, null: false, default: 0
      t.integer :trial_period_days, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :plans, [ :organization_id, :code ], unique: true

    create_table :charges do |t|
      t.references :plan, null: false, foreign_key: true
      t.references :billable_metric, null: false, foreign_key: true
      t.string :pricing_model, null: false
      t.jsonb :properties, null: false, default: {}
      t.string :invoice_display_name
      t.timestamps
    end
    add_index :charges, [ :plan_id, :billable_metric_id ], unique: true
  end
end
