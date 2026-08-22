class CreateWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoints do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :url, null: false
      t.string :secret, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :webhook_deliveries do |t|
      t.references :webhook_endpoint, null: false, foreign_key: true
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.integer :response_code
      t.text :last_error
      t.datetime :deliver_after, null: false
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :webhook_deliveries, [ :status, :deliver_after ]
  end
end
