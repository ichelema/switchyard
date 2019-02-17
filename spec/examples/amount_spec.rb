require 'spec_helper'
require 'functional-light-service/functional/enum'

Amount = FunctionalLightService.enum do
  Due(:amount)
  Paid(:amount)
  Info(:amount)
end

class Amount
  def self.from_f(f)
    f >= 0 ? Amount::Due.new(f) : Amount::Paid.new(-1 * f)
  end
end

FunctionalLightService.impl(Amount) do
  def to_s
    match do
      Due()  { |a| format("%0.2f", a) }
      Paid() { |a| format("-%0.2f", a) }
      Info() { |a| format("(%0.2f)", a) }
    end
  end

  def to_f
    match do
      Info() { |_a| 0 }
      Due()  { |a| a }
      Paid() { |a| -1 * a }
    end
  end

  def +(other)
    raise TypeError "Expected other to be an Amount, got #{other.class}" unless other.is_a? Amount

    Amount.from_f(to_f + other.to_f)
  end
end

describe Amount do
  # rubocop:disable Naming/MethodName
  def Due(a)
    Amount::Due.new(a)
  end

  def Paid(a)
    Amount::Paid.new(a)
  end

  def Info(a)
    Amount::Info.new(a)
  end
  # rubocop:enable Naming/MethodName

  it "due" do
    amount = Amount::Due.new(100.2)
    expect(amount.to_s).to eq "100.20"
  end

  it "paid" do
    amount = Amount::Paid.new(100.1)
    expect(amount.to_s).to eq "-100.10"
  end

  it "paid" do
    amount = Amount::Info.new(100.31)
    expect(amount.to_s).to eq "(100.31)"
  end

  it "+" do
    expect(Due(10) + Paid(20)).to eq Paid(10)
    expect(Due(10) + Paid(10)).to eq Due(0)
    expect(Due(10) + Due(10)).to eq Due(20)
    expect(Paid(10) + Paid(10)).to eq Paid(20)
    expect(Paid(10) + Due(1) + Info(99)).to eq Paid(9)
  end
end
