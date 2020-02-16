require 'spec_helper'
require 'test_doubles'

describe "Organizer should invoke with/reduce from a call method" do
  context "when the organizer does not have a `call` method" do
    it "gives warning" do
      class OrganizerWithoutCallMethod
        extend FunctionalLightService::Organizer

        def self.do_something
          reduce([])
        end
      end
      expect do
        OrganizerWithoutCallMethod.do_something
      end.to output(/The <OrganizerWithoutCallMethod> class is an organizer/).to_stdout
    end
  end

  context "when the organizer has the `call` method" do
    it "does not issue a warning" do
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
