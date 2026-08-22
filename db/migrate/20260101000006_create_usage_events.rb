class CreateUsageEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_events do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :subscription, null: false, foreign_key: true
      t.string :transaction_id, null: false
      t.string :code, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :properties, null: false, default: {}
      t.datetime :created_at, null: false
    end

    # Replaying the same event must never bill twice: the database, not the
    # application, is what makes ingestion idempotent.
    add_index :usage_events, [ :organization_id, :transaction_id ], unique: true

    # Covers the aggregation query for one metric over one billing period.
    add_index :usage_events, [ :subscription_id, :code, :occurred_at ]
  end
end
