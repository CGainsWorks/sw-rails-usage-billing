class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.references :subscription, null: false, foreign_key: true
      t.string :number
      t.string :status, null: false, default: "draft"
      t.string :currency, null: false, default: "GBP"
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.integer :tax_rate_bps, null: false, default: 0
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.datetime :finalized_at
      t.datetime :paid_at
      t.datetime :voided_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    # One invoice per subscription per billing period, enforced by the database
    # so a retried job cannot produce a duplicate.
    add_index :invoices, [ :subscription_id, :period_start ], unique: true
    add_index :invoices, [ :organization_id, :number ], unique: true, where: "number IS NOT NULL"
    add_index :invoices, [ :organization_id, :status ]

    create_table :invoice_line_items do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :charge, foreign_key: true
      t.references :billable_metric, foreign_key: true
      t.string :kind, null: false
      t.string :description, null: false
      t.decimal :quantity, precision: 20, scale: 6, null: false, default: 0
      t.bigint :unit_amount_cents
      t.bigint :amount_cents, null: false, default: 0
      t.jsonb :breakdown, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :invoice_line_items, [ :invoice_id, :position ]
  end
end
