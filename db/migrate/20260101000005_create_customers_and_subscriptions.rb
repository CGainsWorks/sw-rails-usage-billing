class CreateCustomersAndSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :name, null: false
      t.string :email
      t.string :currency, null: false, default: "GBP"
      t.integer :tax_rate_bps, null: false, default: 0
      t.jsonb :billing_address, null: false, default: {}
      t.timestamps
    end
    add_index :customers, [ :organization_id, :external_id ], unique: true

    create_table :subscriptions do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :status, null: false, default: "active"
      t.datetime :started_at, null: false
      t.datetime :terminated_at
      t.timestamps
    end
    add_index :subscriptions, [ :organization_id, :external_id ], unique: true
    add_index :subscriptions, [ :status, :started_at ]
  end
end
