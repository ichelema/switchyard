require 'spec_helper'

describe FunctionalLightService::Enum do
  include FunctionalLightService

  it "can't use value" do
    expect do
      InvalidEnum = FunctionalLightService.enum do
        Unary(:value)
      end
    end .to raise_error ArgumentError
  end

  context "Nullary, Unary, Binary" do
    MyEnym = FunctionalLightService.enum do
      Nullary()
      Unary(:a)
      Binary(:a, :b)
    end

    it "can't instantiate parent" do
      expect { MyEnym.new }.to \
        raise_error NoMethodError, "private method `new' called for MyEnym:Class"
    end

    it "Nullary" do
      n = MyEnym.Nullary

      expect(n).to be_a MyEnym
      expect(n).to be_a MyEnym::Nullary
      expect(n.name).to eq "Nullary"
      expect { n.value }.to raise_error NoMethodError
      expect(n.inspect).to eq "Nullary"
      expect(n.to_s).to eq ""
      expect(n.fmap {}).to eq n
    end

    it "Unary" do
      u = MyEnym::Unary(1)

      expect(u).to be_a MyEnym
      expect(u).to be_a MyEnym::Unary
      expect(u.name).to eq "Unary"
      expect(u.a).to eq 1
      expect(u.value).to eq 1
      expect(u.inspect).to eq "Unary(1)"
      expect(u.to_s).to eq "1"
    end

    it "Binary" do
      # hash
      b = MyEnym::Binary(:a => 1, :b => 2)
      expect(b).to be_a MyEnym
      expect(b).to be_a MyEnym::Binary
      expect(b.name).to eq "Binary"
      expect(b.inspect).to eq "Binary(a: 1, b: 2)"

      expect(b.a).to eq 1
      expect(b.b).to eq 2
      expect(b.value).to eq(:a => 1, :b => 2)

      # values only
      b = MyEnym::Binary(1, 2)
      expect(b.value).to eq(:a => 1, :b => 2)

      # other names are ok
      b = MyEnym::Binary(:c => 1, :d => 2)
      expect(b.value).to eq(:a => 1, :b => 2)

      expect { MyEnym::Binary(1) }.to raise_error ArgumentError
    end

    it "generated enum" do
      expect(MyEnym.variants.sort).to eq %i[Unary Binary Nullary].sort
      expect(MyEnym.constants.sort.inspect).to eq %i[Matcher Unary Binary Nullary].sort.to_s

      b = MyEnym::Binary(:a => 1, :b => 2)

      res =
        MyEnym.match(b) do
          Nullary() { 0 }
          Unary() { |a| a }
          Binary() { |x, y| [x, y] }
        end

      expect(res).to eq [1, 2]

      res =
        b.match do
          Nullary() { 0 }
          Unary() { |a| a }
          Binary() { |x, y| [x, y] }
        end

      expect(res).to eq [1, 2]

      expect do
        b.match do
          Nullary # Nullary is treated as a constant
        end
      end.to raise_error(NameError)

      expect do
        b.match do
          Nullary()
          Unary()
          Binary()
        end
      end.to raise_error ArgumentError, "No block given to `Nullary`"
    end
  end
end
