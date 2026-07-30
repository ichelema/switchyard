# frozen_string_literal: true

module Switchyard
  # Raised when an action requests rollback via {Context#fail_with_rollback!}.
  # The organizer catches this internally and triggers the rollback sequence.
  class FailWithRollbackError < StandardError; end

  # Raised when a required key declared via {Action::Macros#expects} is
  # missing from the context before execution.
  class ExpectedKeysNotInContextError < StandardError; end

  # Raised when a key declared via {Action::Macros#promises} is not
  # produced by a successful action.
  class PromisedKeysNotInContextError < StandardError; end

  # Raised when an `expects` or `promises` key collides with a
  # Switchyard infrastructure key or an existing {Context} method.
  class ReservedKeysInContextError < StandardError; end

  # Raised when the option passed to {Action::Macros#expects} is not
  # named `:default`.
  class UnusableExpectKeyDefaultError < StandardError; end
end
