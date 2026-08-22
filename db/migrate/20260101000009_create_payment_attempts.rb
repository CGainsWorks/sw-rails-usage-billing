class CreatePaymentAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_attempts do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :provider, null: false, default: "simulated"
      t.string :provider_reference
      t.bigint :amount_cents, null: false
      t.string :currency, null: false
      t.string :status, null: false, default: "pending"
      t.string :failure_reason
      t.datetime :processed_at
      t.timestamps
    end
    add_index :payment_attempts, [ :invoice_id, :created_at ]
  end
end
