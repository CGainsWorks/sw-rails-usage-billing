require "rails_helper"

RSpec.describe Billing::GenerateInvoice do
  let(:organization) { create(:organization) }
  let(:metric) { create(:billable_metric, organization: organization, code: "calls", aggregation_type: "count") }
  let(:plan) do
    create(:plan, organization: organization, base_amount_cents: 5_000).tap do |plan|
      create(:charge, plan: plan, billable_metric: metric, pricing_model: "per_unit",
                      properties: { "unit_amount_cents" => 10 })
    end
  end
  let(:customer) { create(:customer, organization: organization, tax_rate_bps: 2_000) }
  let(:subscription) do
    create(:subscription, organization: organization, customer: customer, plan: plan,
                          started_at: Time.zone.parse("2026-01-01 00:00:00 UTC"))
  end
  let(:period) { subscription.closed_billing_periods(up_to: Time.zone.parse("2026-02-10 00:00:00 UTC")).first }

  before do
    3.times do |index|
      create(:usage_event, organization: organization, subscription: subscription, code: "calls",
                           occurred_at: Time.zone.parse("2026-01-10 09:00:00 UTC") + index.minutes)
    end
  end

  it "writes a draft invoice with a line per statement line" do
    invoice = described_class.call(subscription: subscription, period: period)

    expect(invoice).to be_draft
    expect(invoice.number).to be_nil
    expect(invoice.line_items.map(&:kind)).to eq(%w[subscription_fee usage])
    expect(invoice.subtotal_cents).to eq(5_030)
    expect(invoice.tax_cents).to eq(1_006)
    expect(invoice.total_cents).to eq(6_036)
  end

  it "copies the period onto the invoice" do
    invoice = described_class.call(subscription: subscription, period: period)

    expect(invoice.period_start).to eq(period.starts_at)
    expect(invoice.period_end).to eq(period.ends_at)
  end

  it "keeps the pricing breakdown on the line item" do
    invoice = described_class.call(subscription: subscription, period: period)
    usage = invoice.line_items.find { |item| item.kind == "usage" }

    expect(usage.breakdown).to include("model" => "per_unit", "aggregation" => "count")
    expect(usage.billable_metric).to eq(metric)
  end

  it "returns the existing invoice instead of billing the period twice" do
    first = described_class.call(subscription: subscription, period: period)
    second = described_class.call(subscription: subscription, period: period)

    expect(second.id).to eq(first.id)
    expect(subscription.invoices.count).to eq(1)
  end

  it "survives a race that inserts the same period concurrently" do
    described_class.call(subscription: subscription, period: period)

    # Simulate the other worker having committed between the lookup and the
    # insert: the unique index raises and the loser reads the winner's row.
    generator = described_class.new(subscription: subscription, period: period)
    allow(generator).to receive(:find_existing).and_return(nil, Invoice.last)

    expect(generator.call).to eq(subscription.invoices.sole)
    expect(subscription.invoices.count).to eq(1)
  end

  it "does not leave a half written invoice behind when a line fails" do
    statement = Billing::PeriodStatement.call(subscription: subscription, period: period)
    broken = Billing::PeriodStatement::Line.new(
      kind: "not_a_kind", description: "broken", quantity: BigDecimal(1), unit_amount_cents: nil,
      amount_cents: 1, breakdown: {}, charge: nil, billable_metric: nil
    )
    allow(Billing::PeriodStatement).to receive(:call).and_return(statement.with(lines: statement.lines + [ broken ]))

    expect { described_class.call(subscription: subscription, period: period) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(subscription.invoices.count).to eq(0)
    expect(InvoiceLineItem.where(invoice: subscription.invoices).count).to eq(0)
  end
end
