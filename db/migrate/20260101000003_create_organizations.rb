class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :currency, null: false, default: "GBP"
      t.string :timezone, null: false, default: "UTC"
      t.timestamps
    end
    add_index :organizations, :slug, unique: true

    create_table :users do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :email_address, null: false
      t.string :name, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :users, :email_address, unique: true

    create_table :api_keys do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :api_keys, :token_digest, unique: true
    add_index :api_keys, [ :organization_id, :name ], unique: true
  end
end
