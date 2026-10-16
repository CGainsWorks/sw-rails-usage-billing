# Maps a Meterly record to its counterpart at a payment provider, so the
# billing tables stay provider-agnostic: a Stripe customer id never becomes a
# column on customers.
class CreateProviderReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_references do |t|
      t.string :provider, null: false
      t.references :record, polymorphic: true, null: false
      t.string :kind, null: false
      t.string :external_id, null: false
      t.timestamps
    end

    add_index :provider_references, [ :provider, :record_type, :record_id, :kind ], unique: true,
              name: "index_provider_references_on_record_and_kind"
    add_index :provider_references, [ :provider, :kind, :external_id ],
              name: "index_provider_references_on_external_id"
  end
end
