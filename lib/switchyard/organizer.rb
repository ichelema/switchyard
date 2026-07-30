# frozen_string_literal: true

module Switchyard
  # Orchestrates a pipeline of {Action actions}.
  #
  # Extend this module in a class, declare the pipeline with one of the
  # `reduce_*` methods, and define callbacks with {Macros}.
  #
  # @example Minimal organizer
  #   class CalculatePrices
  #     extend Switchyard::Organizer
  #
  #     def self.call(params)
  #       with(params).reduce(steps)
  #     end
  #
  #     def self.steps
  #       [
  #         ValidateInput,
  #         ApplyDiscount,
  #         ComputeTotal,
  #       ]
  #     end
  #   end
  #
  #   result = CalculatePrices.call(:items => [...])
  #
  # @example With declarative callbacks
  #   class OrderWorkflow
  #     extend Switchyard::Organizer
  #
  #     before_actions ->(ctx) { ctx[:started_at] = Time.now }
  #     after_actions  ->(ctx) { AuditLog.write(ctx) }
  #
  #     aliases :order_id => :id
  #   end
  #
  # @see Action
  # @see Context
  # @see WithReducer
  module Organizer
    # Extends the base class with DSL methods and macros.
    #
    # @api private
    # @param base_class [Class]
    # @return [void]
    def self.extended(base_class)
      base_class.extend ClassMethods
      base_class.extend Macros
    end

    # Supports the deprecated `include Switchyard::Organizer` form.
    #
    # @deprecated Use `extend Switchyard::Organizer` instead.
    # @api private
    # @param base_class [Class]
    # @return [void]
    def self.included(base_class)
      Switchyard::Deprecations.warn(
        "Including Switchyard::Organizer is deprecated; " \
        "use `extend Switchyard::Organizer` instead"
      )
      extended(base_class)
    end

    # Methods available on the organizer class to build pipelines and
    # control execution flow.
    module ClassMethods
      # Creates a {WithReducer} with an initial {Context} and the
      # declared aliases and hooks.
      #
      # The returned reducer can be further configured with
      # {WithReducer#around_each} before calling {WithReducer#reduce}.
      #
      # @example
      #   with(:number => 0).reduce([AddOne, AddTwo])
      #
      # @param data [Hash, Context] initial data for the context
      # @return [WithReducer] configured reducer
      def with(data = {})
        data[:_aliases] = @aliases if @aliases

        # Gli hook di classe vengono solo letti (mai azzerati): devono valere
        # per ogni chiamata, anche concorrente
        data[:_before_actions] = @before_actions.dup if @before_actions
        data[:_after_actions] = @after_actions.dup if @after_actions

        WithReducerFactory.make(self).with(data)
      end

      # Shortcut to reduce actions with an empty initial context.
      #
      # Equivalent to `with({}).reduce(actions)`.
      #
      # @param actions [Array<Class, Proc, #call>] steps to execute
      # @return [Context]
      def reduce(*actions)
        with({}).reduce(actions)
      end

      # Executes steps only when a condition block returns `true`.
      #
      # The condition receives the current {Context} and must return a
      # boolean.
      #
      # @example
      #   reduce_if(->(ctx) { ctx.user.present? }, [SendEmail, LogAccess])
      #
      # @param condition_block [Proc] receives the context, returns truthy
      #   when steps should run
      # @param steps [Array<Class, Proc>] actions to execute
      # @return [Array<ReduceIf>] wrapper steps
      def reduce_if(condition_block, steps)
        ReduceIf.run(self, condition_block, steps)
      end

      # Conditionally executes one of two action groups.
      #
      # Like {#reduce_if} with an `else` branch.
      #
      # @example
      #   reduce_if_else(->(ctx) { ctx.paid? },
      #                  [SendReceipt],
      #                  [SendInvoice])
      #
      # @param condition_block [Proc] receives the context, returns truthy
      #   for the `if_steps` branch
      # @param if_steps [Array<Class, Proc>] actions when condition is true
      # @param else_steps [Array<Class, Proc>] actions when condition is false
      # @return [Array<ReduceIfElse>] wrapper steps
      def reduce_if_else(condition_block, if_steps, else_steps)
        ReduceIfElse.run(self, condition_block, if_steps, else_steps)
      end

      # Repeats steps until a condition block returns `true`.
      #
      # The condition is evaluated **after** each iteration.
      #
      # @example
      #   reduce_until(->(ctx) { ctx[:invoices].empty? }, [ProcessNextInvoice])
      #
      # @param condition_block [Proc] receives the context, returns truthy
      #   when the loop should stop
      # @param steps [Array<Class, Proc>] actions to repeat
      # @return [Array<ReduceUntil>] wrapper steps
      def reduce_until(condition_block, steps)
        ReduceUntil.run(self, condition_block, steps)
      end

      # Dispatches execution based on a value in the context.
      #
      # Each key in `args` is a value to match; the corresponding steps
      # run when the dispatch key matches that value.
      #
      # @example
      #   reduce_case(
      #     :on => :status,
      #     "pending"  => [ValidatePayment],
      #     "shipped"  => [NotifyCustomer],
      #     :default   => [LogUnknownStatus]
      #   )
      #
      # @param args [Hash] keyword arguments: `:on` specifies the context key
      #   to read; remaining keys are values to match; use `:default` for
      #   the fallback branch
      # @return [Array<ReduceCase>] wrapper steps
      def reduce_case(**args)
        ReduceCase.run(self, **args)
      end

      # Repeats steps while a condition block returns `true`.
      #
      # The condition is evaluated **before** each iteration.
      #
      # @example
      #   reduce_while(->(ctx) { ctx[:balance] > 0 }, [DeductDues])
      #
      # @param condition_block [Proc] receives the context, returns truthy
      #   while the loop should continue
      # @param steps [Array<Class, Proc>] actions to repeat
      # @return [Array<ReduceWhile>] wrapper steps
      def reduce_while(condition_block, steps)
        ReduceWhile.run(self, condition_block, steps)
      end

      # Iterates over a collection stored in the context.
      #
      # For each item in `ctx[collection_key]`, the singularised key is
      # set on the context and the steps are executed.
      #
      # @example
      #   iterate(:items, [ValidateItem, PriceItem])
      #   # ctx[:item] is set for each element of ctx[:items]
      #
      # @param collection_key [Symbol] context key holding an enumerable
      # @param steps [Array<Class, Proc>] actions to run per item
      # @return [Array<Iterate>] wrapper steps
      def iterate(collection_key, steps)
        Iterate.run(self, collection_key, steps)
      end

      # Wraps a plain block or lambda into an executable step.
      #
      # @example
      #   execute(->(ctx) { ctx[:logged] = true })
      #
      # @param code_block [Proc, nil] a lambda or proc; if omitted the
      #   block passed to the method is used
      # @yield alternative block form
      # @yieldparam ctx [Context]
      # @return [Array<Execute>] wrapper step
      def execute(code_block = nil, &block)
        Execute.run(code_block || block)
      end

      # Wraps steps with a before/after pair.
      #
      # The given action is executed before and after each step in the
      # pipeline. It receives the context and must call `yield` in
      # between (middleware style).
      #
      # @example
      #   with_callback(->(ctx, &blk) { TimeMeasure.measure(ctx, &blk) },
      #                 [FetchData, TransformData])
      #
      # @param action [Proc] middleware that receives the context and a
      #   block to call
      # @param steps [Array<Class, Proc>] actions wrapped by the callback
      # @return [Array<WithCallback>] wrapper steps
      def with_callback(action, steps)
        WithCallback.run(self, action, steps)
      end

      # Sets a custom logger for this organizer.
      #
      # When not set, {Configuration.logger} is used.
      #
      # @param logger [Logger] the logger instance
      # @return [Logger]
      def log_with(logger)
        @logger = logger
      end

      # Returns the custom logger, if set.
      #
      # @return [Logger, nil]
      def logger
        @logger
      end

      # Injects static keys into the context before the pipeline runs.
      #
      # Each key-value pair becomes an action step that writes the value
      # and registers an accessor.
      #
      # @example
      #   add_to_context :currency => "EUR", :locale => "it"
      #
      # @param args [Hash] key-value pairs to add
      # @return [Array<Execute>] one wrapper step per pair
      def add_to_context(**args)
        args.map do |key, value|
          execute(->(ctx) do
            ctx[key.to_sym] = value
            ctx.define_accessor_methods_for_keys([key])
          end)
        end
      end

      # Merges additional key aliases into the existing alias map.
      #
      # @example
      #   add_aliases :email => :mail, :name => :full_name
      #
      # @param args [Hash{Symbol => Symbol}] maps original keys to alias names
      # @return [Array<Execute>] a wrapper step
      def add_aliases(args)
        execute(->(ctx) { ctx.assign_aliases(ctx.aliases.merge(args)) })
      end
    end

    # Declarative class-level macros for the organizer.
    #
    # Use these inside the class body to set up hooks and aliases that
    # apply to every pipeline run.
    module Macros
      # Declares a key alias map for the context.
      #
      # @example
      #   aliases :user_email => :email
      #
      # @param key_hash [Hash{Symbol => Symbol}]
      def aliases(key_hash)
        @aliases = key_hash
      end

      # Declares a proc (or array of procs) to run **before** each action.
      #
      # The proc receives the context; the executed action is available
      # via `ctx.current_action`.
      #
      # @example
      #   before_actions ->(ctx) { ctx[:timings] ||= [] }
      #
      # @param logic [Array<Proc>, Proc] one or more callback procs
      def before_actions(*logic)
        self.before_actions = logic
      end

      # Sets the `before_actions` callbacks.
      #
      # Accepts nil, a single proc, or an array of procs.
      #
      # @param logic [Array<Proc>, Proc, nil]
      def before_actions=(logic)
        @before_actions = logic.nil? ? nil : [logic].flatten
      end

      # Appends a callback to the existing `before_actions` list.
      #
      # @param action [Proc]
      def append_before_actions(action)
        @before_actions ||= []
        @before_actions.push(action)
      end

      # Removes a specific callback from `before_actions`.
      #
      # @param action [Proc]
      def remove_before_actions(action)
        @before_actions&.delete(action)
      end

      # Declares a proc (or array of procs) to run **after** each action.
      #
      # The proc receives the context; the executed action is available
      # via `ctx.current_action`.
      #
      # @example
      #   after_actions ->(ctx) { AuditLog.write(ctx) }
      #
      # @param logic [Array<Proc>, Proc] one or more callback procs
      def after_actions(*logic)
        self.after_actions = logic
      end

      # Sets the `after_actions` callbacks.
      #
      # Accepts nil, a single proc, or an array of procs.
      #
      # @param logic [Array<Proc>, Proc, nil]
      def after_actions=(logic)
        @after_actions = logic.nil? ? nil : [logic].flatten
      end

      # Appends a callback to the existing `after_actions` list.
      #
      # @param action [Proc]
      def append_after_actions(action)
        @after_actions ||= []
        @after_actions.push(action)
      end
    end
  end
end
