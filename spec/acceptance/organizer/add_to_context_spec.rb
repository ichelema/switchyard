require 'spec_helper'

RSpec.describe FunctionalLightService::Organizer do
  class TestAddToContext
    extend FunctionalLightService::Organizer

    def self.call(context = FunctionalLightService::Context.make)
      with(context).reduce(steps)
    end

    def self.steps
      [
        # This will add the `:number` key to the context
        # with the value of 0, so it's available for
        # AddsOneAction
        add_to_context(:number => 0),
        TestDoubles::AddsOneAction,
        add_to_context(:something => "hello")
      ]
    end
  end

  it "adds items to the context on the fly" do
    result = TestAddToContext.call

    expect(result).to be_success
    expect(result.number).to eq(1)
    expect(result[:something]).to eq("hello")
  end

  it "defines accessors for the added keys" do
    result = TestAddToContext.call

    expect(result.something).to eq("hello")
  end

  it "raises when the added key conflicts with a Context method" do
    organizer = Class.new do
      extend FunctionalLightService::Organizer

      def self.call
        reduce(steps)
      end

      def self.steps
        [add_to_context(:message => "boom")]
      end
    end

    expect { organizer.call }
      .to raise_error(FunctionalLightService::ReservedKeysInContextError,
                      /:message conflicts/)
  end
end
