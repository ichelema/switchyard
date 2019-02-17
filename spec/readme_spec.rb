require 'spec_helper'

# rubocop:disable Style/MixinUsage
include FunctionalLightService::Prelude::Result
# rubocop:enable Style/MixinUsage

Success(1).to_s                        # => "1"
Success(Success(1))                    # => Success(1)

Failure(1).to_s                        # => "1"
Failure(Failure(1))                    # => Failure(1)

Success(1).fmap { |v| v + 1 }           # => Success(2)
Failure(1).fmap { |v| v - 1 }           # => Failure(0)

Threenum = FunctionalLightService.enum do
  Nullary()
  Unary(:a)
  Binary(:a, :b)
end

FunctionalLightService.impl(Threenum) do
  def sum
    match do
      Nullary() {        0 }
      Unary()   { |u|    u }
      Binary()  { |a, b| a + b }
    end
  end

  def +(other)
    match do
      Nullary() {        other.sum }
      Unary()   { |_a|   sum + other.sum }
      Binary()  { |_a, _b| sum + other.sum }
    end
  end
end

describe Threenum do
  it "works" do
    expect(Threenum.Nullary + Threenum.Unary(1)).to eq 1
    expect(Threenum.Nullary + Threenum.Binary(2, 3)).to eq 5
    expect(Threenum.Unary(1) + Threenum.Binary(2, 3)).to eq 6
    expect(Threenum.Binary(2, 3) + Threenum.Binary(2, 3)).to eq 10
  end
end
