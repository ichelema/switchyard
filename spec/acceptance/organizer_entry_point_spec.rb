require 'spec_helper'
require 'test_doubles'

describe "Organizer entry point" do
  context "when the organizer entry method is not named `call`" do
    it "works without emitting any warning" do
      class OrganizerWithoutCallMethod
        extend FunctionalLightService::Organizer

        def self.do_something
          reduce([])
        end
      end

      result = nil
      expect { result = OrganizerWithoutCallMethod.do_something }
        .not_to output.to_stdout
      expect(result).to be_a_kind_of(FunctionalLightService::Context)
    end
  end

  context "when the organizer has the `call` method" do
    it "works without emitting any warning" do
      class OrganizerWithCallMethod
        extend FunctionalLightService::Organizer

        def self.call
          reduce([])
        end
      end

      expect(OrganizerWithCallMethod.call).to be_a_kind_of(FunctionalLightService::Context)
    end
  end
end
