# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_01_000010) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_api_keys_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_api_keys_on_organization_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
  end

  create_table "billable_metrics", force: :cascade do |t|
    t.string "aggregation_type", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.jsonb "filters", default: {}, null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "property_name"
    t.datetime "updated_at", null: false
    t.index ["organization_id", "code"], name: "index_billable_metrics_on_organization_id_and_code", unique: true
    t.index ["organization_id"], name: "index_billable_metrics_on_organization_id"
  end

  create_table "charges", force: :cascade do |t|
    t.bigint "billable_metric_id", null: false
    t.datetime "created_at", null: false
    t.string "invoice_display_name"
    t.bigint "plan_id", null: false
    t.string "pricing_model", null: false
    t.jsonb "properties", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["billable_metric_id"], name: "index_charges_on_billable_metric_id"
    t.index ["plan_id", "billable_metric_id"], name: "index_charges_on_plan_id_and_billable_metric_id", unique: true
    t.index ["plan_id"], name: "index_charges_on_plan_id"
  end

  create_table "customers", force: :cascade do |t|
    t.jsonb "billing_address", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "GBP", null: false
    t.string "email"
    t.string "external_id", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.integer "tax_rate_bps", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "external_id"], name: "index_customers_on_organization_id_and_external_id", unique: true
    t.index ["organization_id"], name: "index_customers_on_organization_id"
  end

  create_table "invoice_line_items", force: :cascade do |t|
    t.bigint "amount_cents", default: 0, null: false
    t.bigint "billable_metric_id"
    t.jsonb "breakdown", default: {}, null: false
    t.bigint "charge_id"
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.bigint "invoice_id", null: false
    t.string "kind", null: false
    t.integer "position", default: 0, null: false
    t.decimal "quantity", precision: 20, scale: 6, default: "0.0", null: false
    t.bigint "unit_amount_cents"
    t.datetime "updated_at", null: false
    t.index ["billable_metric_id"], name: "index_invoice_line_items_on_billable_metric_id"
    t.index ["charge_id"], name: "index_invoice_line_items_on_charge_id"
    t.index ["invoice_id", "position"], name: "index_invoice_line_items_on_invoice_id_and_position"
    t.index ["invoice_id"], name: "index_invoice_line_items_on_invoice_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "GBP", null: false
    t.bigint "customer_id", null: false
    t.datetime "finalized_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "number"
    t.bigint "organization_id", null: false
    t.datetime "paid_at"
    t.datetime "period_end", null: false
    t.datetime "period_start", null: false
    t.string "status", default: "draft", null: false
    t.bigint "subscription_id", null: false
    t.bigint "subtotal_cents", default: 0, null: false
    t.bigint "tax_cents", default: 0, null: false
    t.integer "tax_rate_bps", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.datetime "voided_at"
    t.index ["customer_id"], name: "index_invoices_on_customer_id"
    t.index ["organization_id", "number"], name: "index_invoices_on_organization_id_and_number", unique: true, where: "(number IS NOT NULL)"
    t.index ["organization_id", "status"], name: "index_invoices_on_organization_id_and_status"
    t.index ["organization_id"], name: "index_invoices_on_organization_id"
    t.index ["subscription_id", "period_start"], name: "index_invoices_on_subscription_id_and_period_start", unique: true
    t.index ["subscription_id"], name: "index_invoices_on_subscription_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "GBP", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.string "timezone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "payment_attempts", force: :cascade do |t|
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.string "failure_reason"
    t.bigint "invoice_id", null: false
    t.datetime "processed_at"
    t.string "provider", default: "simulated", null: false
    t.string "provider_reference"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["invoice_id", "created_at"], name: "index_payment_attempts_on_invoice_id_and_created_at"
    t.index ["invoice_id"], name: "index_payment_attempts_on_invoice_id"
  end

  create_table "plans", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "base_amount_cents", default: 0, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "GBP", null: false
    t.string "description"
    t.string "interval", default: "monthly", null: false
    t.bigint "minimum_amount_cents", default: 0, null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.integer "trial_period_days", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "code"], name: "index_plans_on_organization_id_and_code", unique: true
    t.index ["organization_id"], name: "index_plans_on_organization_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.integer "completed_jobs", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "enqueued_at"
    t.datetime "failed_at"
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "finished_at"
    t.text "metadata"
    t.text "on_failure"
    t.text "on_finish"
    t.text "on_success"
    t.integer "total_jobs", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.bigint "batch_id"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.string "external_id", null: false
    t.bigint "organization_id", null: false
    t.bigint "plan_id", null: false
    t.datetime "started_at", null: false
    t.string "status", default: "active", null: false
    t.datetime "terminated_at"
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_subscriptions_on_customer_id"
    t.index ["organization_id", "external_id"], name: "index_subscriptions_on_organization_id_and_external_id", unique: true
    t.index ["organization_id"], name: "index_subscriptions_on_organization_id"
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["status", "started_at"], name: "index_subscriptions_on_status_and_started_at"
  end

  create_table "usage_events", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "occurred_at", null: false
    t.bigint "organization_id", null: false
    t.jsonb "properties", default: {}, null: false
    t.bigint "subscription_id", null: false
    t.string "transaction_id", null: false
    t.index ["organization_id", "transaction_id"], name: "index_usage_events_on_organization_id_and_transaction_id", unique: true
    t.index ["organization_id"], name: "index_usage_events_on_organization_id"
    t.index ["subscription_id", "code", "occurred_at"], name: "index_usage_events_on_subscription_id_and_code_and_occurred_at"
    t.index ["subscription_id"], name: "index_usage_events_on_subscription_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.string "password_digest", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["organization_id"], name: "index_users_on_organization_id"
  end

  create_table "webhook_deliveries", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "deliver_after", null: false
    t.datetime "delivered_at"
    t.string "event_type", null: false
    t.text "last_error"
    t.jsonb "payload", default: {}, null: false
    t.integer "response_code"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "webhook_endpoint_id", null: false
    t.index ["status", "deliver_after"], name: "index_webhook_deliveries_on_status_and_deliver_after"
    t.index ["webhook_endpoint_id"], name: "index_webhook_deliveries_on_webhook_endpoint_id"
  end

  create_table "webhook_endpoints", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "organization_id", null: false
    t.string "secret", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["organization_id"], name: "index_webhook_endpoints_on_organization_id"
  end

  create_table "webhook_sink_receipts", force: :cascade do |t|
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "received_at", null: false
    t.boolean "signature_valid", default: false, null: false
    t.index ["event_type", "received_at"], name: "index_webhook_sink_receipts_on_event_type_and_received_at"
  end

  add_foreign_key "api_keys", "organizations"
  add_foreign_key "billable_metrics", "organizations"
  add_foreign_key "charges", "billable_metrics"
  add_foreign_key "charges", "plans"
  add_foreign_key "customers", "organizations"
  add_foreign_key "invoice_line_items", "billable_metrics"
  add_foreign_key "invoice_line_items", "charges"
  add_foreign_key "invoice_line_items", "invoices"
  add_foreign_key "invoices", "customers"
  add_foreign_key "invoices", "organizations"
  add_foreign_key "invoices", "subscriptions"
  add_foreign_key "payment_attempts", "invoices"
  add_foreign_key "plans", "organizations"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "subscriptions", "customers"
  add_foreign_key "subscriptions", "organizations"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "usage_events", "organizations"
  add_foreign_key "usage_events", "subscriptions"
  add_foreign_key "users", "organizations"
  add_foreign_key "webhook_deliveries", "webhook_endpoints"
  add_foreign_key "webhook_endpoints", "organizations"
end
