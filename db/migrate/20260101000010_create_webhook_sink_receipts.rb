# The sink is a development and test affordance: it lets the application
# receive its own webhooks so the delivery path can be verified end to end
# without a third-party service. The route is not mounted in production.
class CreateWebhookSinkReceipts < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_sink_receipts do |t|
      t.string :event_type, null: false
      t.boolean :signature_valid, null: false, default: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :received_at, null: false
    end
    add_index :webhook_sink_receipts, [ :event_type, :received_at ]
  end
end
