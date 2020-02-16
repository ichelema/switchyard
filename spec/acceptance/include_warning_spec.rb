require 'spec_helper'

describe "Including is discouraged" do
  context "when including FunctionalLightService::Organizer" do
    it "gives warning" do
      expected_msg = "DEPRECATION WARNING:\n" \
                     "Including FunctionalLightService::Organizer is deprecated\n" \
                     "Please use `extend FunctionalLightService::Organizer` instead"
      expect do
        class OrganizerIncludingLS
          include FunctionalLightService::Organizer
        end
      end.to output(expected_msg).to_stdout
    end
  end

  context "when including FunctionalLightService::Action" do
    it "gives warning" do
      expected_msg = "DEPRECATION WARNING:\n" \
                     "Including FunctionalLightService::Action is deprecated\n" \
                     "Please use `extend FunctionalLightService::Action` instead"
      expect do
        class ActionIncludingLS
          include FunctionalLightService::Action
        end
      end.to output(expected_msg).to_stdout
    end
  end
end
