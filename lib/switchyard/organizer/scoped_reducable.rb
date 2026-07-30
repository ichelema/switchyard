# frozen_string_literal: true

module Switchyard
  module Organizer
    # Provides a scoped reduce for nested pipeline constructs.
    #
    # Resets the `skip_remaining` flag before and after the sub-pipeline
    # so that a `skip_remaining!` call only affects the current scope
    # (e.g. one iteration of {Iterate} or one branch of {ReduceIf}).
    # The `skip_all_remaining!` flag is **never** reset here — it
    # propagates to outer scopes.
    #
    # @see Context#skip_all_remaining!
    #
    module ScopedReducable
      # Runs a sub-pipeline with scoped `skip_remaining` semantics.
      #
      # @param organizer [Module] the owning organizer
      # @param ctx [Context] current context
      # @param steps [Array<Class, Proc>] steps for the sub-pipeline
      # @return [Context]
      def scoped_reduce(organizer, ctx, steps)
        ctx.reset_skip_remaining! unless ctx.failure? || ctx.skip_all_remaining?
        ctx = organizer.with(ctx).reduce([steps])
        ctx.reset_skip_remaining! unless ctx.failure? || ctx.skip_all_remaining?

        ctx
      end
    end
  end
end
