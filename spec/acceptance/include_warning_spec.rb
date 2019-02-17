require 'spec_helper'

describe "Including is discouraged" do
  context "when including FunctionalLightService::Organizer" do
    it "gives warning" do
      expected_msg = "including FunctionalLightService::Organizer is deprecated. " \
                     "Please use `extend FunctionalLightService::Organizer` instead"
      expect(ActiveSupport::Deprecation).to receive(:warn)
        .with(expected_msg)

      class OrganizerIncludingLS
        include FunctionalLightService::Organizer
      end
    end
  end

  context "when including FunctionalLightService::Action" do
    it "gives warning" do
      expected_msg = "including FunctionalLightService::Action is deprecated. " \
                     "Please use `extend FunctionalLightService::Action` instead"
      expect(ActiveSupport::Deprecation).to receive(:warn)
        .with(expected_msg)

      class ActionIncludingLS
        include FunctionalLightService::Action
      end
    end
  end
end
