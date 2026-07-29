require 'spec_helper'
# Maybe()/Null e il monkey-patch di Object sono opt-in: non fanno parte
# del require chain di default della gem
require 'switchyard/functional/maybe'

describe "deprecation warnings" do
  around do |example|
    Switchyard::Deprecations.silenced = false
    Switchyard::Deprecations.reset!
    example.run
  ensure
    Switchyard::Deprecations.silenced = true
    Switchyard::Deprecations.reset!
  end

  context "when including Switchyard::Organizer" do
    it "warns on stderr" do
      expect do
        class OrganizerIncludingLS
          include Switchyard::Organizer
        end
      end.to output(/Including Switchyard::Organizer is deprecated/).to_stderr
    end
  end

  context "when including Switchyard::Action" do
    it "warns on stderr" do
      expect do
        class ActionIncludingLS
          include Switchyard::Action
        end
      end.to output(/Including Switchyard::Action is deprecated/).to_stderr
    end
  end

  context "when using Maybe/Null" do
    it "warns once per process" do
      expect { Maybe(nil) }
        .to output(%r{Maybe\(\)/Null are deprecated}).to_stderr
      # warn-once: la seconda invocazione non emette nulla
      expect { Maybe(nil) }.not_to output.to_stderr
    end
  end

  context "when using the exotic operators" do
    include Switchyard::Prelude::Result

    it "Result#>= warns and delegates to #try" do
      result = nil
      expect { result = Success(1) >= ->(v) { Success(v + 1) } }
        .to output(/Result#>= is deprecated/).to_stderr
      expect(result).to eq(Success(2))
    end

    it "Result#<< warns and delegates to #pipe" do
      expect { Success(1) << ->(_v) {} }
        .to output(/Result#<< is deprecated/).to_stderr
    end

    it "Result#+ warns and still combines" do
      result = nil
      expect { result = Success(1) + Success(2) }
        .to output(/Result#\+ is deprecated/).to_stderr
      expect(result).to eq(Success(3))
    end

    it "Option#+ warns and still combines" do
      some = Switchyard::Option::Some
      result = nil
      expect { result = some.new(1) + some.new(2) }
        .to output(/Option#\+ is deprecated/).to_stderr
      expect(result).to eq(some.new(3))
    end
  end

  context "when silenced" do
    it "emits nothing" do
      Switchyard::Deprecations.silenced = true
      expect { Maybe(nil) }.not_to output.to_stderr
    end
  end
end
