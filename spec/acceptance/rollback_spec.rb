require 'spec_helper'
require 'test_doubles'

class RollbackOrganizer
  extend FunctionalLightService::Organizer

  def self.call(number)
    with(:number => number).reduce(
      AddsOneWithRollbackAction,
      TestDoubles::AddsTwoAction,
      AddsThreeWithRollbackAction
    )
  end
end

class AddsOneWithRollbackAction
  extend FunctionalLightService::Action

  expects :number
  promises :number

  executed do |context|
    context.fail_with_rollback! if context.number.zero?

    context.number += 1
  end

  rolled_back do |context|
    context.number -= 1
  end
end

class AddsThreeWithRollbackAction
  extend FunctionalLightService::Action

  expects :number

  executed do |context|
    context.number = context.number + 3

    context.fail_with_rollback!("I did not like this!")
  end

  rolled_back do |context|
    context.number -= 3
  end
end

class RollbackOrganizerWithNoRollback
  extend FunctionalLightService::Organizer

  def self.call(number)
    with(:number => number).reduce(
      TestDoubles::AddsOneAction,
      TestDoubles::AddsTwoAction,
      AddsThreeWithNoRollbackAction
    )
  end
end

class AddsThreeWithNoRollbackAction
  extend FunctionalLightService::Action

  expects :number

  executed do |context|
    context.number = context.number + 3

    context.fail_with_rollback!("I did not like this!")
  end
end

class RollbackOrganizerWithMiddleRollback
  extend FunctionalLightService::Organizer

  def self.call(number)
    with(:number => number).reduce(
      TestDoubles::AddsOneAction,
      AddsTwoActionWithRollback,
      TestDoubles::AddsThreeAction
    )
  end
end

class AddsTwoActionWithRollback
  extend FunctionalLightService::Action

  expects :number

  executed do |context|
    context.number = context.number + 2

    context.fail_with_rollback!("I did not like this a bit!")
  end

  rolled_back do |context|
    context.number -= 2
  end
end

class RollbackOrganizerWithDuplicatedAction
  extend FunctionalLightService::Organizer

  def self.call(ctx)
    with(ctx).reduce(
      TracksRollbackAction,
      FailsOnSecondRunWithRollbackAction,
      TracksRollbackAction,
      FailsOnSecondRunWithRollbackAction
    )
  end
end

class TracksRollbackAction
  extend FunctionalLightService::Action

  executed do |context|
    (context[:executed] ||= []) << :tracks
  end

  rolled_back do |context|
    (context[:rolled_back] ||= []) << :tracks
  end
end

class FailsOnSecondRunWithRollbackAction
  extend FunctionalLightService::Action

  executed do |context|
    (context[:executed] ||= []) << :fails
    context.fail_with_rollback!("boom") if context[:executed].count(:fails) == 2
  end

  rolled_back do |context|
    (context[:rolled_back] ||= []) << :fails
  end
end

describe "Rolling back actions when there is a failure" do
  it "Adds 1, 2, 3 to 1 and rolls back " do
    result = RollbackOrganizer.call 1
    number = result.fetch(:number)

    expect(result).to be_failure
    expect(result.message).to eq("I did not like this!")
    expect(number).to eq(3)
  end

  it "won't error out when actions don't define rollback" do
    result = RollbackOrganizerWithNoRollback.call 1
    number = result.fetch(:number)

    expect(result).to be_failure
    expect(result.message).to eq("I did not like this!")
    expect(number).to eq(7)
  end

  it "rolls back properly when triggered with an action in the middle" do
    result = RollbackOrganizerWithMiddleRollback.call 1
    number = result.fetch(:number)

    expect(result).to be_failure
    expect(result.message).to eq("I did not like this a bit!")
    expect(number).to eq(2)
  end

  it "rolls back from the first action" do
    result = RollbackOrganizer.call 0
    number = result.fetch(:number)

    expect(result).to be_failure
    expect(number).to eq(-1)
  end

  it "rolls back every executed action when the same action appears twice" do
    result = RollbackOrganizerWithDuplicatedAction.call({})

    expect(result).to be_failure
    expect(result[:executed]).to eq(%i[tracks fails tracks fails])
    # tutte e 4 le azioni eseguite vengono compensate, in ordine inverso
    expect(result[:rolled_back]).to eq(%i[fails tracks fails tracks])
  end
end
