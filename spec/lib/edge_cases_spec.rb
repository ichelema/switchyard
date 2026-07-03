require 'spec_helper'
require 'functional-light-service/functional/maybe'

# Copertura dei path d'errore e delle API minori emersi dall'audit
describe "edge cases and error paths" do
  include FunctionalLightService::Prelude::Result
  include FunctionalLightService::Prelude::Option

  describe FunctionalLightService::Context do
    it "#add_to_context merges values" do
      ctx = FunctionalLightService::Context.make(:a => 1)
      ctx.add_to_context(:b => 2)

      expect(ctx[:b]).to eq(2)
    end
  end

  describe FunctionalLightService::Context::KeyVerifier do
    it "the base verifier requires throw_error_predicate to be overridden" do
      ctx = FunctionalLightService::Context.make
      verifier = described_class.new(ctx, nil)

      expect { verifier.throw_error_predicate([]) }.to raise_error(NotImplementedError)
    end
  end

  describe "Object monkey patch (opt-in via functional/maybe)" do
    it "defines null? and some? on every object" do
      expect("anything".null?).to be(false)
      expect("anything".some?).to be(true)
    end
  end

  describe Null do
    it "class-level unknown messages return the singleton" do
      expect(Null.anything_at_all).to eq(Null.instance)
    end

    it "class-level respond_to? is permissive" do
      expect(Null.respond_to?(:anything_at_all)).to be(true)
    end

    it "compares equal to another Null" do
      expect(Null.instance == Null.instance).to be(true) # rubocop:disable Lint/BinaryOperatorWithIdenticalOperands
      expect(Null.instance == "not null").to be(false)
    end

    it "a mimic only responds to the mimicked interface" do
      klass = Class.new { def foo; end }
      mimic = Null.mimic(klass)

      expect(mimic.respond_to?(:foo)).to be(true)
      expect(mimic.respond_to?(:bar)).to be(false)
      expect { mimic.bar }.to raise_error(NoMethodError)
    end
  end

  describe "enum error paths" do
    it "raises when a variant is defined twice" do
      expect do
        FunctionalLightService.enum do
          Dup()
          Dup()
        end
      end.to raise_error(ArgumentError, /already defined/)
    end

    it "the enum builder responds to any variant name" do
      builder = FunctionalLightService::EnumBuilder.new(Class.new)

      expect(builder.respond_to?(:AnyVariantName)).to be(true)
    end

    it "raises MatchError when the match is not exhaustive" do
      expect do
        Some(1).match do
          Some() { |s| s }
        end
      end.to raise_error(FunctionalLightService::Enum::MatchError, /non-exhaustive/)
    end

    it "raises MatchError when the block arity does not match the variant" do
      expect do
        Some(1).match do
          Some() { |a, b| [a, b] }
          None() { nil }
        end
      end.to raise_error(FunctionalLightService::Enum::MatchError, /must match/)
    end

    it "raises MatchError when no guard matches" do
      expect do
        Some(1).match do
          Some(where { s > 100 }) { |s| s }
          None() { nil }
        end
      end.to raise_error(FunctionalLightService::Enum::MatchError, /No match could be made/)
    end

    it "rejects unnamed/rest block parameters" do
      # su Ruby 3.1 |*| appare come [[:rest]] (ramo "Unnamed param"),
      # da Ruby 3.2 come [[:rest, :*]] (ramo "Only :req & :opt")
      expect do
        Some(1).match do
          Some() { |*| nil }
          None() { nil }
        end
      end.to raise_error(ArgumentError, /Unnamed param|Only :req & :opt/)
    end

    it "rejects keyword block parameters" do
      expect do
        Some(1).match do
          Some() { |**opts| opts }
          None() { nil }
        end
      end.to raise_error(ArgumentError, /Only :req & :opt params allowed/)
    end

    it "None deconstructs to an empty hash and array" do
      none = FunctionalLightService::Option::None.new

      expect(none.deconstruct).to eq([])
      expect(none.deconstruct_keys(nil)).to eq({})
    end
  end

  describe "Option minor APIs" do
    it "#value_to_a returns the raw value" do
      expect(Some(1).value_to_a).to eq(1)
      expect(FunctionalLightService::Option::None.new.value_to_a).to be_nil
    end

    it "Prelude None() builds the shared None" do
      expect(None().none?).to be(true)
    end

    it "Prelude Option() returns the Option enum" do
      expect(Option()).to eq(FunctionalLightService::Option)
    end
  end

  describe "Result minor APIs" do
    it "#+ raises NotMonadError for non-Result operands" do
      expect { Success(1) + "not a result" } # rubocop:disable Style/StringConcatenation
        .to raise_error(FunctionalLightService::Monad::NotMonadError)
    end

    it "Prelude try! wraps exceptions in Failure" do
      result = try! { raise "boom" }

      expect(result).to be_failure
      expect(result.value).to be_a(RuntimeError)
    end
  end
end
