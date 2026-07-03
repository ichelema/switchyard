require 'spec_helper'
require 'test_doubles'

RSpec.describe FunctionalLightService::Context do
  let(:context) { FunctionalLightService::Context.make }

  describe "can be made" do
    context "with no arguments" do
      subject { FunctionalLightService::Context.make }
      it { is_expected.to be_success }
      specify "message is empty string" do
        expect(context.message).to be_empty
      end
    end

    context "with a hash" do
      it "has the hash values" do
        context = FunctionalLightService::Context.make(:one => 1)

        expect(context[:one]).to eq(1)
      end
    end

    context "with FAILURE" do
      it "is failed" do
        outcome = FunctionalLightService::Result::Failure(:message => '', :error => nil)
        context = FunctionalLightService::Context.new({}, outcome)

        expect(context).to be_failure
      end
    end
  end

  describe "can't be made" do
    specify "with invalid parameters" do
      expect { FunctionalLightService::Context.make([]) }.to raise_error(ArgumentError)
    end
  end

  it "can be asked for success?" do
    outcome = FunctionalLightService::Result::Success(:message => '', :error => nil)
    context = FunctionalLightService::Context.new({}, outcome)

    expect(context).to be_success
  end

  it "can be asked for failure?" do
    outcome = FunctionalLightService::Result::Failure(:message => '', :error => nil)
    context = FunctionalLightService::Context.new({}, outcome)

    expect(context).to be_failure
  end

  it "can be asked for skip_remaining?" do
    context.skip_remaining!

    expect(context.skip_remaining?).to be_truthy
  end

  it "can be pushed into a SUCCESS state" do
    context.succeed!("a happy end")

    expect(context).to be_success
  end

  it "can be pushed into a SUCCESS state without a message" do
    context.succeed!

    expect(context).to be_success
    expect(context.message).to be_nil
  end

  it "can be pushed into a FAILURE state without a message" do
    context.fail!

    expect(context).to be_failure
    expect(context.message).to be_nil
  end

  it "can be pushed into a FAILURE state with a message" do
    context.fail!("a sad end")

    expect(context).to be_failure
  end

  it "can be pushed into a FAILURE state with a message in an options hash" do
    context.fail!("a sad end")

    expect(context).to be_failure
    expect(context.message).to eq("a sad end")
    expect(context.error_code).to be_nil
  end

  it "can be pushed into a FAILURE state with an error code in options hash" do
    context.fail!("a sad end", 10_005)

    expect(context).to be_failure
    expect(context.message).to eq("a sad end")
    expect(context.error_code).to eq(10_005)
  end

  it "uses localization adapter to translate failure message" do
    action_class = TestDoubles::AnAction
    expect(FunctionalLightService::Configuration.localization_adapter)
      .to receive(:failure)
      .with(:failure_reason, action_class, {})
      .and_return("message")

    context = FunctionalLightService::Context.make
    context.current_action = action_class
    context.fail!(:failure_reason)

    expect(context).to be_failure
    expect(context.message).to eq("message")
  end

  it "uses localization adapter to translate success message" do
    action_class = TestDoubles::AnAction
    expect(FunctionalLightService::Configuration.localization_adapter)
      .to receive(:success)
      .with(:action_passed, action_class, {})
      .and_return("message")

    context = FunctionalLightService::Context.make
    context.current_action = action_class
    context.succeed!(:action_passed)

    expect(context).to be_success
    expect(context.message).to eq("message")
  end

  it "can set a flag to skip all subsequent actions" do
    context.skip_remaining!

    expect(context).to be_skip_remaining
  end

  context "stopping additional processing in an action" do
    it "flags processing to stop on failure" do
      context.fail!("on purpose")
      expect(context.stop_processing?).to be_truthy
    end

    it "flags processing to stop when remaining actions should be skipped" do
      context.skip_remaining!
      expect(context.stop_processing?).to be_truthy
    end
  end

  it "can fail with FailWithRollBackError" do
    expect { context.fail_with_rollback!("roll me back") }.to \
      raise_error(FunctionalLightService::FailWithRollbackError)
  end

  it "exptected outcome reader get Success and message empty and error nil" do
    outcome = FunctionalLightService::Result::Success(:message => "", :error => nil)
    expect(context.outcome).to eq(outcome)
  end

  it "can contain false values" do
    context = FunctionalLightService::Context.make(:foo => false)
    expect(context[:foo]).to eq false
  end

  it "allows a default value for #fetch" do
    expect(context.fetch(:madeup, :default)).to eq(:default)
  end

  it "allows a default block value for #fetch" do
    # la forma a blocco e' esattamente cio' che il test verifica
    expect(context.fetch(:madeup) { :default }).to eq(:default) # rubocop:disable Style/RedundantFetchBlock
  end

  describe "#define_accessor_methods_for_keys" do
    it "raises when a key conflicts with an existing Hash/Context method" do
      expect { context.define_accessor_methods_for_keys([:size]) }
        .to raise_error(FunctionalLightService::ReservedKeysInContextError, /:size conflicts/)
    end

    it "does not raise when re-defining accessors for the same key" do
      ctx = FunctionalLightService::Context.make(:number => 1)
      ctx.define_accessor_methods_for_keys([:number])

      expect { ctx.define_accessor_methods_for_keys([:number]) }.not_to raise_error
      expect(ctx.number).to eq(1)
    end
  end

  describe "reserved keys" do
    it "rejects infrastructure keys in expects/promises" do
      action = Class.new do
        extend FunctionalLightService::Action

        expects :_before_actions
        executed { |_ctx| } # rubocop:disable Lint/EmptyBlock
      end

      expect { action.execute(:_before_actions => []) }
        .to raise_error(FunctionalLightService::ReservedKeysInContextError)
    end
  end

  describe "#fail! does not mutate the caller's options hash" do
    it "leaves :error_code in the original hash" do
      options = { :error_code => 500 }
      context.fail!("boom", options)

      expect(options).to eq(:error_code => 500)
      expect(context.error_code).to eq(500)
    end
  end

  describe "#reset_skip_remaining!" do
    it "clears the flag but keeps the outcome and its message" do
      context.skip_remaining!("No need to process")
      context.reset_skip_remaining!

      expect(context.skip_remaining?).to be(false)
      expect(context).to be_success
      expect(context.message).to eq("No need to process")
    end
  end

  describe "#fetch honours the Hash#fetch contract" do
    it "raises KeyError for a missing key without default" do
      expect { context.fetch(:madeup) }.to raise_error(KeyError)
    end

    it "does not write to the context when a default is used" do
      context.fetch(:madeup, :default)
      context.fetch(:another_madeup) { :default } # rubocop:disable Style/RedundantFetchBlock

      expect(context.to_h).not_to have_key(:madeup)
      expect(context.to_h).not_to have_key(:another_madeup)
    end

    it "returns existing falsy values instead of the default" do
      context = FunctionalLightService::Context.make(:flag => false)

      expect(context.fetch(:flag, true)).to eq(false)
    end
  end

  context "when aliases are included via .make" do
    let(:context) do
      FunctionalLightService::Context.make(
        :foo => "foobar",
        :foo2 => false,
        :_aliases => aliases
      )
    end
    let(:aliases) { { :foo => :bar, :foo2 => :bar2 } }

    it "contains the aliases" do
      expect(context.aliases).to eq(aliases)
      expect(context).to include(:foo, :bar)
    end

    it "returns the correct values for #[] and #fetch" do
      expect(context[:bar]).to eq context[:foo]
      expect(context.fetch(:bar)).to eq context[:foo]
    end

    it "can contain false values" do
      expect(context[:bar2]).to eq false
    end

    it "resolves aliases on writes too, symmetrically with reads" do
      context[:bar] = "updated"

      expect(context[:bar]).to eq("updated")
      expect(context[:foo]).to eq("updated")
      # nessuna chiave duplicata: l'alias e' un nome alternativo, non una copia
      expect(context.to_h).not_to have_key(:bar)
    end

    it "resolves aliases in #key? and friends" do
      expect(context.key?(:bar)).to be(true)
      expect(context.has_key?(:bar)).to be(true) # rubocop:disable Style/PreferredHashMethods
      expect(context.member?(:bar)).to be(true)
      expect(context.include?(:bar)).to be(true)
      expect(context.key?(:madeup)).to be(false)
    end

    it "resolves aliases in #fetch with defaults" do
      expect(context.fetch(:bar, :default)).to eq("foobar")
    end
  end
end
