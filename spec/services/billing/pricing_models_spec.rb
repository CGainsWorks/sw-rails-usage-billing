require "rails_helper"

RSpec.describe Billing::PricingModels do
  def price(model, properties, quantity)
    described_class.build(model, properties).call(BigDecimal(quantity.to_s))
  end

  describe "per unit" do
    let(:properties) { { "unit_amount_cents" => "0.05", "free_units" => 1_000 } }

    it "charges nothing while usage stays inside the free allowance" do
      expect(price("per_unit", properties, 1_000).amount_cents).to eq(0)
    end

    it "charges only the units above the allowance" do
      expect(price("per_unit", properties, 21_000).amount_cents).to eq(1_000)
    end

    it "rounds a fractional total half up, once" do
      # 1_005 units at 0.05c is 50.25c, which has to become 50 and not 51.
      expect(price("per_unit", { "unit_amount_cents" => "0.05" }, 1_005).amount_cents).to eq(50)
      expect(price("per_unit", { "unit_amount_cents" => "0.05" }, 1_010).amount_cents).to eq(51)
    end

    it "reports the arithmetic in the breakdown" do
      breakdown = price("per_unit", properties, 2_500).breakdown

      expect(breakdown).to include("model" => "per_unit", "billable_quantity" => "1500.0")
    end
  end

  describe "package" do
    let(:properties) { { "package_size" => 1_000, "package_amount_cents" => 250, "free_units" => 0 } }

    it "bills a part-used package as a whole package" do
      expect(price("package", properties, 1_001).amount_cents).to eq(500)
    end

    it "bills an exact multiple without rounding up" do
      expect(price("package", properties, 3_000).amount_cents).to eq(750)
    end

    it "bills nothing for no usage" do
      expect(price("package", properties, 0).amount_cents).to eq(0)
    end
  end

  describe "graduated tiers" do
    let(:properties) do
      { "tiers" => [
        { "up_to" => 10_000, "unit_amount_cents" => "0.5" },
        { "up_to" => 50_000, "unit_amount_cents" => "0.3", "flat_amount_cents" => 100 },
        { "up_to" => nil, "unit_amount_cents" => "0.1" }
      ] }
    end

    it "slices the quantity at the tier boundaries" do
      # 10_000 * 0.5 + 2_000 * 0.3 + one flat 100
      expect(price("tiered", properties, 12_000).amount_cents).to eq(5_000 + 600 + 100)
    end

    it "stops at the first tier when usage is small" do
      expect(price("tiered", properties, 4_000).amount_cents).to eq(2_000)
    end

    it "reaches the unbounded tier" do
      expected = (10_000 * 0.5) + (40_000 * 0.3) + 100 + (10_000 * 0.1)
      expect(price("tiered", properties, 60_000).amount_cents).to eq(expected.round)
    end

    it "records every tier it touched" do
      tiers = price("tiered", properties, 12_000).breakdown["tiers"]

      expect(tiers.length).to eq(2)
      expect(tiers.first).to include("units" => "10000.0", "amount_cents" => 5_000)
    end

    it "charges nothing for zero usage" do
      expect(price("tiered", properties, 0).amount_cents).to eq(0)
    end
  end

  describe "volume" do
    let(:properties) do
      { "tiers" => [
        { "up_to" => 1_000, "unit_amount_cents" => 12 },
        { "up_to" => 10_000, "unit_amount_cents" => 9 },
        { "up_to" => nil, "unit_amount_cents" => 6 }
      ] }
    end

    it "prices every unit at the rate the total reached" do
      expect(price("volume", properties, 1_500).amount_cents).to eq(1_500 * 9)
    end

    it "can make a larger quantity cheaper than a smaller one" do
      expect(price("volume", properties, 10_001).amount_cents).to be < price("volume", properties, 10_000).amount_cents
    end

    it "uses the boundary tier inclusively" do
      expect(price("volume", properties, 1_000).amount_cents).to eq(1_000 * 12)
    end
  end

  describe "validation" do
    it "rejects a per unit price without an amount" do
      expect(described_class.build("per_unit", {}).validation_errors).to include(/unit_amount_cents/)
    end

    it "rejects a package with no size" do
      expect(described_class.build("package", { "package_amount_cents" => 10 }).validation_errors)
        .to include(/package_size/)
    end

    it "rejects tiers that do not end with an open tier" do
      properties = { "tiers" => [ { "up_to" => 10, "unit_amount_cents" => 1 } ] }

      expect(described_class.build("tiered", properties).validation_errors).to include(/last tier/)
    end

    it "rejects tier boundaries that do not increase" do
      properties = { "tiers" => [
        { "up_to" => 100, "unit_amount_cents" => 1 },
        { "up_to" => 50, "unit_amount_cents" => 1 },
        { "up_to" => nil, "unit_amount_cents" => 1 }
      ] }

      expect(described_class.build("volume", properties).validation_errors).to include(/increase/)
    end

    it "accepts a well formed tier list" do
      properties = { "tiers" => [ { "up_to" => 10, "unit_amount_cents" => 1 }, { "up_to" => nil, "unit_amount_cents" => 1 } ] }

      expect(described_class.build("tiered", properties).validation_errors).to be_empty
    end
  end

  it "refuses to price a negative quantity" do
    expect { price("per_unit", { "unit_amount_cents" => 1 }, -1) }.to raise_error(ArgumentError)
  end

  it "raises for an unknown model" do
    expect { described_class.build("guesswork", {}) }.to raise_error(ArgumentError)
  end
end
