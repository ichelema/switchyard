# FunctionalLightService

[![Gem Version](https://img.shields.io/gem/v/functional-light-service.svg)](https://rubygems.org/gems/functional-light-service)
[![CI Tests](https://github.com/sphynx79/functional-light-service/actions/workflows/project-build.yml/badge.svg)](https://github.com/sphynx79/functional-light-service/actions/workflows/project-build.yml)
[![Codecov](https://codecov.io/gh/sphynx79/functional-light-service/branch/master/graph/badge.svg)](https://app.codecov.io/gh/sphynx79/functional-light-service)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](http://opensource.org/licenses/MIT)
[![Download Count](https://img.shields.io/gem/dt/functional-light-service)](https://rubygems.org/gems/functional-light-service)

## Table of Content

* [Requirements](#requirements)
* [Installation](#installation)
* [Why FunctionalLightService?](#why-functionallightservice?)
* [Stopping the Series of Actions](#stopping-the-series-of-actions)
  * [Failing the Context](#failing-the-context)
  * [Skipping the Rest of the Actions](#skipping-the-rest-of-the-actions)
* [Benchmarking Actions with Around Advice](#benchmarking-actions-with-around-advice)
* [Before and After Action Hooks](#before-and-after-action-hooks)
* [Key Aliases](#key-aliases)
* [Logging](#logging)
* [Error Codes](#error-codes)
* [Action Rollback](#action-rollback)
* [Localizing Messages](#localizing-messages)
* [Logic in Organizers](#logic-in-organizers)
* [ContextFactory for Faster Action Testing](#contextfactory-for-faster-action-testing)
* [Functional programming](#functional-programming)
  * [Pattern](#pattern)
  * [Usage](#functional-usage)
    * [Result: Success & Failure](#functional-usage-success-failure)
    * [Result Chaining](#functional-usage-chaining)
    * [Sequencing (do-notation)](#functional-usage-sequencing)
    * [Complex Example in a Builder Action](#functional-usage-complex-action)
    * [Pattern matching](#functional-usage-pattern-matching)
    * [Option](#functional-usage-option)
    * [Coercion](#functional-usage-coercion)
    * [Enum](#functional-usage-enum)
    * [Maybe](#functional-usage-maybe)
* [Usage](#usage)

## Requirements

This gem requires ruby >= 3.1 (tested up to ruby 4.0)

## Installation

Add this line to your application's Gemfile:

```bash
    gem 'functional-light-service'
```

And then execute:

```bash
    $ bundle
```

Or install it yourself as:

```bash
    $ gem install functional-light-service
```

## Why FunctionalLightService?

While studying functional programming in Ruby, I discovered the fantastic gem **Deterministic**, which made it much easier to write Ruby code in a functional style.  
By leveraging its `in_sequence` method, I can chain a series of actions:

- If every step completes without raising an exception, the call returns a `Success()` monad.
- If any step fails, the remaining actions are skipped and a `Failure()` monad is returned.

I writing this code:

```ruby
class Foo
  include Deterministic::Prelude

  def call(input)
    result = in_sequence do
      get(:sanitized_input) { sanitize(input) }
      and_then              { validate(sanitized_input) }
      and_then              { connect_db }
      get(:user)            { get_user(sanitized_input) }
      and_yield             { print_response(user) }
    end
    logger.warn(result.value) if result.failure?
  rescue StandardError => e
    logger.fatal(e.message)
  end

  def sanitize(input)
    sanitized_input = {}
    sanitized_input[:name] = input[:name].downcase
    sanitized_input[:password] = input[:password].downcase
    Success(sanitized_input)
  end

  def validate(sanitized_input)
    try!  do
      raise "Not allow empty name" if sanitized_input[:name].empty?
      raise "Not allow empty password" if sanitized_input[:password].empty?
    end.map_err { |n| Failure(n.message) }
  end

  def connect_db
    try! do
      raise "Error connection to db" if rand(0..1) == 1
    end.map_err { |n| Failure(n.message) }
  end

  def get_user(sanitized_input)
    user = FAKEDB.find do |_k, v|
      sanitized_input[:name] == v[:name] && sanitized_input[:password] == v[:password]
    end
    user.nil? ? Failure("Name or password error") : Success(user)
  end

  def print_response(user)
    Success(logger.info("Login successful id: #{user[0]} name: #{user[1][:name]}"))
  end
end

Foo.new.call(:name => "foo", :password => "bar")
```

While refactoring my codebase, I needed each action to live in a well‑defined context.  
That’s when I discovered the excellent gem **LightService**. It gives me exactly what I was looking for:

- a clean separation between business concerns and orchestration logic
- a simple way to arrange actions in a pipeline
- the freedom to place every action in its own class, each with its own contextual data

```ruby
class Foo
  extend LightService::Organizer

  def self.call(name: "", password: "")
    result = with(:name => name, :password => password).reduce(actions)
    logger.warn(result.message) if result.failure?
  end

  def self.actions
    [
      Sanitize,
      Validate,
      ConnectDb,
      GetUser,
      PrintResponse
    ]
  end
end

class Sanitize
  extend LightService::Action
  expects :name, :password
  promises :sanitized_input

  executed do |ctx|
    sanitized_input = {}
    sanitized_input[:name] = ctx.name.downcase
    sanitized_input[:password] = ctx.password.downcase
    ctx.sanitized_input = sanitized_input
  end
end

class Validate
  extend LightService::Action
  expects :sanitized_input

  executed do |ctx|
    ctx.fail_and_return!("Not allow empty name") if ctx.sanitized_input[:name].empty?
    ctx.fail_and_return!("Not allow empty password") if ctx.sanitized_input[:password].empty?
  end
end

class ConnectDb
  extend LightService::Action

  executed do |ctx|
    raise "Error connection to db"
  rescue StandardError => e
    ctx.fail!(e.message) if rand(0..1) == 1
  end

  # private_class_method :..
end

class GetUser
  extend LightService::Action
  expects :sanitized_input
  promises :user

  executed do |ctx|
    user = FAKEDB.find do |_k, v|
      ctx.sanitized_input[:name] == v[:name] && ctx.sanitized_input[:password] == v[:password]
    end
    ctx.fail_and_return!("Name or password error") if user.nil?
    ctx.user = user
  end
end

class PrintResponse
  extend LightService::Action
  expects :user

  executed do |ctx|
    logger.info("Login successful id: #{ctx.user[0]} name: #{ctx.user[1][:name]}")
  end
end

Foo.call(:name => "foo", :password => "bar")
```

The switch to **LightService** came at a price: I missed the functional‑programming super‑powers that **Deterministic** had given me.  
So I asked myself, *why not enjoy the best of both worlds?*  
That question led me to create **this gem**. Now I can keep all the conveniences LightService offers—action pipelines, clear contexts—while still coding in a fully functional style with expressive monads.

```ruby
class Foo
  extend FunctionalLightService::Organizer

  def self.call(name: "", password: "")
    result = with(:name => name, :password => password).reduce(actions)
    logger.warn(result.message) if result.failure?
  end

  def self.actions
    [
      Sanitize,
      Validate,
      ConnectDb,
      GetUser,
      PrintResponse
    ]
  end
end

class Sanitize
  extend FunctionalLightService::Action
  expects :name, :password
  promises :sanitized_input

  executed do |ctx|
    name = ctx.name
    password = ctx.password
    ctx.sanitized_input = downcase(name, password).value
  end

  def self.downcase(name, password)
    ctx.try! do
      {
        :name => name.downcase,
        :password => password.downcase
      }
    end.map_err { ctx.fail!("Error nel method downcase") }
  end

  private_class_method :downcase
end

class Validate
  extend FunctionalLightService::Action
  expects :sanitized_input

  executed do |ctx|
    validate_params(ctx.sanitized_input).match do
      None() { ctx.Success(0) }
      Some() { |errors| ctx.fail_and_return!(errors) }
    end
  end

  def self.validate_params(params)
    return ctx.Some("Not allow empty name") if ctx.Option.any?(params[:name]).none?
    return ctx.Some("Not allow empty password") if ctx.Option.any?(params[:password]).none?

    ctx.None
  end

  private_class_method :validate_params
end

class ConnectDb
  extend FunctionalLightService::Action

  executed do |ctx|
    ctx.try! do
      raise "Error connection to db" if rand(0..1) == 1
    end.map_err { |n| ctx.fail!(n.message) }
  end
end

class GetUser
  extend FunctionalLightService::Action
  expects :sanitized_input
  promises :user

  executed do |ctx|
    user = Success(ctx.sanitized_input[:name]) >> method(:fetch_name) >> method(:check_password)
    ctx.user = user.value
  end

  def self.fetch_name(name)
    records = FAKEDB.select { |_k, v| name == v[:name] }
    ctx.fail_and_return!("Name not found in DB") if records.empty?

    Success(records)
  end

  def self.check_password(records)
    record = records.select { |_k, v| ctx.sanitized_input[:password] == v[:password] }
    return ctx.fail_and_return!("Password is not correct") if record.empty?

    Success(record)
  end

  private_class_method :fetch_name, :check_password
end

class PrintResponse
  extend FunctionalLightService::Action
  expects :user

  executed do |ctx|
    id = ctx.user.keys[0]
    name = ctx.user.values[0][:name]
    logger.info("Login successful id: #{id} name: #{name}")
  end
end

Foo.call(:name => "foo", :password => "bar")
```

## Stopping the Series of Actions

When everything goes smoothly, the organizer returns a **successful** context.  
You can check it like this:

```ruby
class SomeController < ApplicationController
  def index
    result_context = SomeOrganizer.call(current_user.id)

    if result_context.success?
      redirect_to foo_path, :notice => "Everything went OK! Thanks!"
    else
      flash[:error] = result_context.message
      render :action => "new"
    end
  end
end
```

Sometimes, though, things don’t go as planned — an external API is down or a business rule fails.  
In those cases, you can short‑circuit the pipeline in two ways:

1. **Fail the context** – aborts execution and returns a `Failure()` monad with an error message.
2. **Skip the remaining actions** – stops further actions but keeps the context successful, allowing graceful exits without raising an error.

### Failing the Context

When an action hits an unrecoverable error, call `context.fail!` to mark the context as failed (`context.failure? #=> true`) and abort the pipeline.  
You can pass an optional message to describe what went wrong:

```ruby
context.fail!("Validation failed")
```

If you also need to leave the executed block immediately, you have two options:

- next context – after fail!, simply return the context.
- context.fail_and_return!(msg) – a one‑liner that sets the failure state and exits the block.

Here is an example:

```ruby
class SubmitsOrderAction
  extend FunctionalLightService::Action
  expects :order, :mailer

  executed do |context|
    unless context.order.submit_order_successful?
      context.fail_and_return!("Failed to submit the order")
    end

    # This won't be executed
    context.mailer.send_order_notification!
  end
end
```

![fail-actions](https://raw.githubusercontent.com/sphynx79/functional-light-service/master/resources/fail_actions.png)

In the example above the organizer called 4 actions. The first 2 actions got executed successfully. The 3rd had a failure, that pushed the context into a failure state and the 4th action was skipped.

### Skipping the rest of the actions

To short‑circuit the pipeline without marking the context as failed, call
`context.skip_remaining!`. It behaves like `fail!`, but the context
remains **successful**, so downstream code can still treat the result as OK.

Typical use case: you run the first few actions, perform a check, and if everything
is already fine you can avoid processing the rest.

```ruby
class ChecksOrderStatusAction
  extend FunctionalLightService::Action
  expects :order

  executed do |context|
    if context.order.send_notification?
      context.skip_remaining!("Everything is good, no need to execute the rest of the actions")
    end
  end
end
```

![skip-actions](https://raw.githubusercontent.com/sphynx79/functional-light-service/master/resources/skip_actions.png)

In the example above, the organizer invokes four actions.
The first two run successfully; the third calls skip_remaining!, so the fourth is never executed, yet the overall context stays successful.

### Skipping everything, including nested scopes

`skip_remaining!` is scoped: constructs like `reduce_if` or `iterate` reset it
at their boundary, so it only exits the **current** scope. When you need to stop
the whole organizer from inside a nested construct, use
`context.skip_all_remaining!` — it is never reset, so every remaining step (in
the current scope and in the outer ones) is skipped while the context stays
successful:

```ruby
class StopsEverythingAction
  extend FunctionalLightService::Action
  expects :item

  executed do |context|
    if context.item.poison_pill?
      context.skip_all_remaining!("Poison pill found, stopping the pipeline")
    end
  end
end
```

## Benchmarking Actions with Around Advice

When you need to profile a pipeline, adding timing code inside every single
action clutters your business logic.  
Instead, use the organizer’s `around_each` hook, which wraps each action call
as it is reduced in order.

```ruby
class LogDuration
  def self.call(context)
    start_time = Time.now
    result = yield           # run the wrapped action
    duration = Time.now - start_time
    FunctionalLightService::Configuration.logger.info(
      :action   => context.current_action,
      :duration => duration
    )

    result
  end
end

class CalculatesTax
  extend FunctionalLightService::Organizer

  def self.call(order)
    with(:order => order).around_each(LogDuration).reduce(
        LooksUpTaxPercentageAction,
        CalculatesOrderTaxAction,
        ProvidesFreeShippingAction
      )
  end
end
```

Any object you pass to around_each must implement:

```ruby
def self.call(context, &block)
  # …before logic…
  result = yield   # executes the action
  # …after logic…
  result
end
```

This design lets you measure—or audit—every action without polluting
the actions themselves.

## Before and After Action Hooks

Sometimes you need to run code **right before** or **right after** each action.  
FunctionalLightService lets you do that with the `before_actions` and `after_actions` hooks.  
Each hook accepts one (or many) lambdas that will be invoked by the organizer, keeping
instrumentation neatly separated from business logic.

### Example without hooks

```ruby
class SomeOrganizer
  extend FunctionalLightService::Organizer

  def self.call(ctx)
    with(ctx).reduce(actions)
  end

  def self.actions
    [
      OneAction,
      TwoAction,
      ThreeAction
    ]
  end
end

class TwoAction
  extend FunctionalLightService::Action
  expects :user, :logger

  executed do |ctx|
    # Logging information
    if ctx.user.role == 'admin'
       ctx.logger.info('admin is doing something')
    end

    ctx.user.do_something
  end
end
```

Logging overwhelms the real work in TwoAction.
Let’s move that concern into hooks.

### Option 1 — declare hooks inside the organizer

```ruby
class SomeOrganizer
  extend FunctionalLightService::Organizer
  before_actions (lambda do |ctx|
                           if ctx.current_action == TwoAction
                             return unless ctx.user.role == 'admin'
                             ctx.logger.info('admin is doing something')
                           end
                         end)
  after_actions (lambda do |ctx|
                          if ctx.current_action == TwoAction
                            return unless ctx.user.role == 'admin'
                            ctx.logger.info('admin is DONE doing something')
                          end
                        end)

  def self.call(ctx)
    with(ctx).reduce(actions)
  end

  def self.actions
    [
      OneAction,
      TwoAction,
      ThreeAction
    ]
  end
end

class TwoAction
  extend FunctionalLightService::Action
  expects :user

  executed do |ctx|
    ctx.user.do_something
  end
end
```

Now TwoAction is pure business logic.
Because ctx.current_action holds the class of the action being run, the hooks fire
only for TwoAction, not OneAction or ThreeAction.

### Option 2 — attach hooks from the outside

```ruby
SomeOrganizer.before_actions =
  lambda do |ctx|
    if ctx.current_action == TwoAction
      return unless ctx.user.role == 'admin'
      ctx.logger.info('admin is doing something')
    end
  end
```

These ideas are originally from Aspect Oriented Programming, read more about them [here](https://en.wikipedia.org/wiki/Aspect-oriented_programming).

## Expects and Promises

Two handy macros define the contract of every action:

| Macro      | Purpose                                                         |
| ---------- | --------------------------------------------------------------- |
| `expects`  | Declares which keys **must** be present before the action runs. |
| `promises` | Declares which keys **must** exist after the action finishes.   |

If either rule is violated, FunctionalLightService raises a dedicated exception.

### Basic usage

```ruby
class FooAction
  extend FunctionalLightService::Action

  expects   :baz
  promises  :bar

  executed do |context|
    baz = context.fetch(:baz)   # guaranteed to be present
    context[:bar] = baz + 2     # fulfils the promise
  end
end
```

### Built‑in readers and writers

The macros do more than validation:
expects adds an accessor reader, so you can reference keys directly.
promises adds an accessor writer, so you can assign without touching the hash.
Refactored, the action is cleaner:

```ruby
class FooAction
  extend FunctionalLightService::Action

  expects   :baz
  promises  :bar

  executed do |context|
    context.bar = context.baz + 2
  end
end
```

Want to see it in practice? Check out [this spec](spec/action_expects_and_promises_spec.rb) test file.

### Default values for expected keys

An expected key can declare a `default`, used when the key is missing from the
context (also when the action runs inside an organizer). The default can be a
static value or a lambda receiving the context:

```ruby
class GreetsSomeoneAction
  extend FunctionalLightService::Action

  expects :name
  expects :greeting, :default => "Hello"
  expects :message,  :default => ->(ctx) { "#{ctx[:greeting]}, #{ctx[:name]}!" }

  executed do |context|
    puts context.message
  end
end

GreetsSomeoneAction.execute(:name => "Rick") # ⇒ "Hello, Rick!"
```

Note that `expects` accepts a single key when a default is given, and any
keyword other than `default` raises `UnusableExpectKeyDefaultError` at class
definition time. Keys already reachable through an alias are considered
present, so their default is not applied.

## Key Aliases

Need to wire together actions that use different key names?  
Declare key mappings once in the organizer with the `aliases` macro and every
action can read or write the value under its preferred name.

```ruby
class AnOrganizer
  extend FunctionalLightService::Organizer

  aliases :my_key => :key_alias

  def self.call(order)
    with(:order => order).reduce(
      AnAction,
      AnotherAction,
    )
  end
end

class AnAction
  extend FunctionalLightService::Action
  promises :my_key

  executed do |context|
    context.my_key = "value"
  end
end

class AnotherAction
  extend FunctionalLightService::Action
  expects :key_alias

  executed do |context|
    context.key_alias # => "value"
  end
end
```

## Logging

Turning on logging is the easiest way to see what happens inside a pipeline:  
which organizer is called, which actions run, which keys appear in the context, and when something goes wrong.

Logging is **disabled by default**. Enable it in your app’s configuration:

```ruby
FunctionalLightService::Configuration.logger = Logger.new(STDOUT)
```

To silence it, point the logger at nil or /dev/null:

```ruby
FunctionalLightService::Configuration.logger = Logger.new('/dev/null')
```

Run an organizer and you’ll see output like:

```bash
I, [DATE]  INFO -- : [FunctionalLightService] - calling organizer <TestDoubles::MakesTeaAndCappuccino>
I, [DATE]  INFO -- : [FunctionalLightService] -     keys in context: :tea, :milk, :coffee
I, [DATE]  INFO -- : [FunctionalLightService] - executing <TestDoubles::MakesTeaWithMilkAction>
I, [DATE]  INFO -- : [FunctionalLightService] -   expects: :tea, :milk
I, [DATE]  INFO -- : [FunctionalLightService] -   promises: :milk_tea
I, [DATE]  INFO -- : [FunctionalLightService] -     keys in context: :tea, :milk, :coffee, :milk_tea
I, [DATE]  INFO -- : [FunctionalLightService] - executing <TestDoubles::MakesLatteAction>
I, [DATE]  INFO -- : [FunctionalLightService] -   expects: :coffee, :milk
I, [DATE]  INFO -- : [FunctionalLightService] -   promises: :latte
I, [DATE]  INFO -- : [FunctionalLightService] -     keys in context: :tea, :milk, :coffee, :milk_tea, :latte
```

The log provides a blueprint of the series of actions. You can see what organizer is invoked, what actions
are called in what order, what do the expect and promise and most importantly what keys you have in the context
after each action is executed.

Failures are logged at WARN level:

```bash
W, [DATE]  WARN -- : [FunctionalLightService] - :-((( <TestDoubles::MakesLatteAction> has failed...
W, [DATE]  WARN -- : [FunctionalLightService] - context message: Can't make a latte from a milk that's too hot!
```

Skipping the remaining actions is also reported:

```bash
I, [DATE]  INFO -- : [FunctionalLightService] - calling organizer <TestDoubles::MakesCappuccinoSkipsAddsTwo>
I, [DATE]  INFO -- : [FunctionalLightService] -     keys in context: :milk, :coffee
I, [DATE]  INFO -- : [FunctionalLightService] - ;-) <TestDoubles::MakesLatteAction> has decided to skip the rest of the actions
I, [DATE]  INFO -- : [FunctionalLightService] - context message: Can't make a latte with a fatty milk like that!
```

Need different log destinations per organizer? Override the global logger:

```ruby
class FooOrganizer
  extend FunctionalLightService::Organizer
  log_with Logger.new("/my/special.log")
end
```

## Error Codes

Sometimes you need more structure than a free‑text error message.
fail! and fail_and_return! accept an error_code: keyword so you can branch on well‑defined codes later.

```ruby
class FooAction
  extend FunctionalLightService::Action

  executed do |context|
    result = external_service.call

    unless result.success?
      context.fail!(
        "Service call failed",
        error_code: 1001
      )
    end

    unless entity.save
      context.fail!(
        "Saving the entity failed",
        error_code: 2001
      )
    end
  end
end
```

Organizers or downstream actions can then react to specific codes:

```ruby
result = FooOrganizer.call

case result.error_code
when 1001 then retry_later
when 2001 then alert_ops_team
end
```

## Action Rollback

Sometimes an action must **undo** its work if a later step fails.  
Example: one action saves records to the database, the next calls an external
API. If the API call blows up, you want to delete the records you just saved.
That’s exactly what the `rolled_back` macro is for.

```ruby
class SaveEntities
  extend FunctionalLightService::Action
  expects :user

  executed do |context|
    context.user.save!
  end

  rolled_back do |context|
    context.user.destroy
  end
end
```

Trigger a rollback by calling context.fail_with_rollback!.
Rollback begins with the failing action and walks back through the already
executed actions in reverse order.

```ruby
class CallExternalApi
  extend FunctionalLightService::Action

  executed do |context|
    api_call_result = SomeAPI.save_user(context.user)

    context.fail_with_rollback!("Error when calling external API") if api_call_result.failure?
  end
end
```

Declaring rolled_back is optional. If an action makes no persistent changes,
there’s nothing to undo—skip it.

### Using rollbackable actions standalone

When an action is executed outside an organizer via .execute, any
fail_with_rollback! will raise a FailWithRollbackError (an organizer needs
the exception to traverse the chain).

If you don’t want to wrap the call in begin … rescue, check whether the
action is running inside an organizer:

```ruby
class FooAction
  extend FunctionalLightService::Action

  executed do |context|
    # context.organized_by will be nil if run from an action,
    # or will be the class name if run from an organizer
    if context.organized_by.nil?
      context.fail!
    else
      context.fail_with_rollback!
    end
  end
end
```

For a full example, see [this acceptance test](spec/acceptance/rollback_spec.rb) 

## Localizing Messages

Symbols passed to `fail!`/`succeed!` are looked up through a localization
adapter. Two adapters ship with the gem:

- **Built-in adapter** (default): resolves messages from
  `FunctionalLightService::LocalizationMap.instance`, a plain hash keyed by
  `Configuration.locale` (default `:en`) — no extra dependency needed:

  ```ruby
  FunctionalLightService::LocalizationMap.instance[:en] = {
    :foo_action => {
      :light_service => {
        :failures => { :exceeded_api_limit => "Exceeded API limit" },
        :successes => { :api_call_ok => "All good" }
      }
    }
  }
  ```

- **I18n adapter**: selected automatically when your application loads the
  `i18n` gem (it is no longer a runtime dependency of this gem — add it to
  your own Gemfile if you want I18n-backed lookups).

If your app needs something more advanced, you can swap in a custom
localization adapter.

```ruby
class FooAction
  extend FunctionalLightService::Action

  executed do |context|
    unless service_call.success?
      context.fail!(:exceeded_api_limit)

      # The failure message used here equates to:
      # I18n.t(:exceeded_api_limit, scope: "foo_action.light_service.failures")
    end
  end
end
```

### Nested classes

Look‑ups follow ActiveSupport’s underscore, just like Rails models inside modules:

```ruby
module PaymentGateway
  class CaptureFunds
    extend FunctionalLightService::Action

    executed do |context|
      context.fail!(:funds_not_available) if api_service.failed?
      # resolves to:
      # I18n.t(:funds_not_available,
      #        scope: "payment_gateway/capture_funds.light_service.failures")
    end
  end
end
```

### Interpolation variables

Pass a hash for dynamic values:

```ruby
module PaymentGateway
  class CaptureFunds
    extend FunctionalLightService::Action

    executed do |context|
      if api_service.failed?
        context.fail!(:funds_not_available, last_four: "1234")
      end
    end
  end
end
```

```yaml
# en.yml
payment_gateway:
  capture_funds:
    light_service:
      failures:
        funds_not_available: "Unable to process your payment for account ending in %{last_four}"
```

### Custom adapter

Need a different lookup scheme? Subclass the built‑in adapter and set it in the
configuration:

```ruby
# config/initializers/light_service.rb
FunctionalLightService::Configuration.localization_adapter = MyLocalizer.new

# lib/my_localizer.rb
class MyLocalizer < FunctionalLightService::I18n::LocalizationAdapter
  # change default scope to: "light_service.failures.<class_path>"
  def i18n_scope_from_class(action_class, type)
    "light_service.#{type.pluralize}.#{action_class.name.underscore}"
  end
end
```

### Retrieving the message

After an action halts with fail! or succeed!, read the translated text via:

```ruby
result = FooAction.execute(baz: 1)
puts result.message   # ⇒ "Exceeded API limit" (or localized equivalent)
```

## Logic in Organizers

The Organizer - Action combination works really well for simple use cases. However, as business logic gets more complex, or when FunctionalLightService is used in an ETL workflow, the code that routes the different organizers becomes very complex and imperative. Let's look at a piece of code that does basic data transformations:

```ruby
class ExtractsTransformsLoadsData
  def self.run(connection)
    context = RetrievesConnectionInfo.call(connection)
    context = PullsDataFromRemoteApi.call(context)

    retrieved_items = context.retrieved_items
    if retrieved_items.empty?
      NotifiesEngineeringTeamAction.execute(context)
    end

    retrieved_items.each do |item|
      context[:item] = item
      TransformsData.call(context)
    end

    context = LoadsData.call(context)

    SendsNotifications.call(context)
  end
end
```

### Declarative version

```ruby
class ExtractsTransformsLoadsData
  extend FunctionalLightService::Organizer

  def self.call(connection)
    with(:connection => connection).reduce(actions)
  end

  def self.actions
    [
      RetrievesConnectionInfo,
      PullsDataFromRemoteApi,
      reduce_if(->(ctx) { ctx.retrieved_items.empty? }, [
        NotifiesEngineeringTeamAction
      ]),
      iterate(:retrieved_items, [
        TransformsData
      ]),
      LoadsData,
      SendsNotifications
    ]
  end
end
```

The declarative style is shorter, easier to scan, and keeps flow control out of
your actions.

### Organizer constructs

| Construct                                                          | Declarative “equivalent” | What it does (in one line)                                                                  |
| ------------------------------------------------------------------ | ------------------------ | ------------------------------------------------------------------------------------------- |
| [reduce_until](spec/acceptance/organizer/reduce_until_spec.rb)     | `until` loop             | Keeps reducing the listed steps **until** the lambda returns `true`.                        |
| [reduce_while](spec/acceptance/organizer/reduce_while_spec.rb)     | `while` guard            | Checks the lambda **before each step** and stops as soon as it returns `false`.             |
| [reduce_if](spec/acceptance/organizer/reduce_if_spec.rb)           | `if`                     | Reduces its sub‑steps **only if** the lambda returns `true`.                                |
| [reduce_if_else](spec/acceptance/organizer/reduce_if_else_spec.rb) | `if/else`                | Reduces the first list of steps when the lambda is `true`, the second one otherwise.        |
| [reduce_case](spec/acceptance/organizer/reduce_case_spec.rb)       | `case/when`              | Dispatches to the steps matching a context value (`:value`, `:when`, `:else` kwargs).       |
| [iterate](spec/acceptance/organizer/iterate_spec.rb)               | `each` loop              | Loops over a collection key; each element is exposed under the **singular** name.           |
| [execute](spec/acceptance/organizer/execute_spec.rb)               | one‑off lambda           | Runs an inline lambda or block for quick context tweaks (add keys, transform values, etc.). |
| [with_callback](spec/acceptance/organizer/with_callback_spec.rb)   | streaming callback       | Defers execution like a SAX parser—great for huge inputs without loading everything in RAM. |
| [add_to_context](spec/acceptance/organizer/add_to_context_spec.rb) | N/A (context inject)     | Injects key–value pairs into the context (defining accessors) before the next steps run.    |
| [add_aliases](spec/acceptance/organizer/add_aliases_spec.rb)       | key aliasing             | Creates an alias so actions can read/write the same value under different names.            |

All ten are covered by acceptance tests in spec/acceptance/organizer/*_spec.rb.

**Tip**: When iterating, the collection must already be in the context.
iterate(:items) expects context[:items]; it then places each element under
context.item for the inner actions.

```ruby
iterate(:items, [ProcessItem])
# Inside ProcessItem → context.item
```

Need a quick context mutation? Use execute, with a lambda or a block:

```ruby
execute(->(c) { c[:some_values] = c.some_hash.values })
# or
execute { |c| c[:some_values] = c.some_hash.values }
```

Need to branch on a context value? Use reduce_case:

```ruby
reduce_case :value => :status,
            :when => {
              :active   => [NotifiesUserAction],
              :archived => [ArchivesRecordAction]
            },
            :else => [RaisesUnknownStatusAction]
```

## ContextFactory for Faster Action Testing

As workflows grow more complex, building a realistic
`FunctionalLightService::Context` for unit tests can become painful.
Factory objects help, but the data you assemble by hand may still differ
from what earlier actions really produce—especially in ETL pipelines where
each step mutates the context.

### Example pipeline:

```ruby
class SomeOrganizer
  extend FunctionalLightService::Organizer

  def self.call(ctx)
    with(ctx).reduce(actions)
  end

  def self.actions
    [
       ETL::ParsesPayloadAction,
       ETL::BuildsEnititiesAction,
       ETL::SetsUpMappingsAction,
       ETL::SavesEntitiesAction,
       ETL::SendsNotificationAction
    ]
  end
end
```

You should test your workflow from the outside, invoking the organizer’s `call` method and verify that the data was properly created or updated in your data store. However, sometimes you need to zoom into one action, and setting up the context to test it is tedious work. This is where `ContextFactory` can be helpful.

### Enter ContextFactory

FunctionalLightService::Testing::ContextFactory can generate a
pre-populated context that mirrors real runtime data, letting you focus on
the behaviour you want to test.

```ruby
require "spec_helper"
require "light-service/testing"

RSpec.describe ETL::SetsUpMappingsAction do
  let(:context) do
    FunctionalLightService::Testing::ContextFactory
      .make_from(SomeOrganizer)          # build the full pipeline
      .for(described_class)              # stop right before our action
      .with(payload: File.read("spec/data/payload.json"))
  end

  it "sets up mappings correctly" do
    result = described_class.execute(context)
    expect(result).to be_success
  end
end
```

No more 20-line fixture setup—just a realistic context ready to go.

If your organizer contains additional logic in its own call method,
create a test-only organizer inside your specs. 
See [acceptance test](spec/acceptance/testing/context_factory_spec.rb#L4-L11) for a full example.

## Functional Programming

FunctionalLightService lets you write **confident**, side-effect-aware Ruby by
offering monads and algebraic data types (ADTs) you can compose and pattern-match
without boilerplate.

### Pattern Overview

| Monad / ADT                      | When to use it                                                                                                          | Typical flow control                            |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| **Result** (`Success / Failure`) | An operation can **succeed or fail** and the *value matters* either way.                                                | Short-circuit on the first `Failure`.           |
| **Option** (`Some / None`)       | An operation may return **a value or nothing**, and *why it’s missing doesn’t matter*. Think collections or cache hits. | Run every step, keep only the `Some` results.   |
| **Maybe**                        | Wrap any object that *might be `nil`* to avoid endless `nil?` checks.                                                   | Chain safe calls; `Null` swallows method calls. |
| **Enums** (custom ADTs)          | Define your own tagged unions when the built-ins don’t fit.                                                             | Full pattern-matching support.                  |

### Usage

### Result – `Success / Failure` <a name="functional-usage-success-failure"></a>

```ruby
Success(1).to_s                        # => "1"
Success(Success(1))                    # => Success(1)

Failure(1).to_s                        # => "1"
Failure(Failure(1))                    # => Failure(1)
```

#### Mapping and binding

```ruby
Success(1).fmap { |v| v + 1 }                     # => Success(2)
Failure(1).bind { |v| Success(v - 1) }            # => Success(0)

Success(1).map     { |n| Success(n + 1) }         # => Success(2)
Failure(1).map_err { |n| Success(n + 1) }         # => Success(2)
```

#### Flow helpers

```ruby
Success(1).and Success(2)                         # => Success(2)
Success(1).and_then { Success(2) }                # => Success(2)

Failure(1).or Success(99)                         # => Success(99)
Failure(1).or_else { |n| Success(n + 1) }         # => Success(2)
```

#### Exception capturing

```ruby
include FunctionalLightService::Prelude::Result

try! { 1 }                             # => Success(1)
try! { raise "hell" }                  # => Failure(#<RuntimeError: hell>)
try! { risky_call }                    # => Success(result) or Failure(err)
```

### Result Chaining <a name="functional-usage-chaining"></a>

You can easily chain the execution of several operations. Here we got some nice function composition.
The method must be a unary function, i.e. it always takes one parameter - the context, which is passed from call to call.

The following aliases are defined

```ruby
alias :>> :map
alias :<< :pipe
```

This allows the composition of procs or lambdas and thus allow a clear definiton of a pipeline.

```ruby
Success(params) >>
  validate >>
  build_request << log >>
  send << log >>
  build_response
```

### Sequencing (do-notation) – `in_sequence` <a name="functional-usage-sequencing"></a>

When a pipeline needs the intermediate values of earlier steps, chaining alone
gets awkward. `in_sequence` (ported from the [deterministic](https://github.com/pzol/deterministic)
gem, MIT License) gives you a do-notation style block: each step returns a
`Result`, the sequence short-circuits on the first `Failure`, and values bound
with `get`/`let` are available to all subsequent steps by name.

```ruby
class DownloadRemit
  include FunctionalLightService::Prelude

  def call(row)
    in_sequence do
      get(:url)      { extract_url(row) }        # binds the Success value to :url
      get(:file)     { fetch(url) }              # :url is available here
      let(:name)     { File.basename(url) }      # binds a plain (non-Result) value
      and_then       { validate(file) }          # step without binding
      observe        { logger.info("got #{name}") } # side effect, return value ignored
      and_yield      { Success(name) }           # final result of the sequence
    end
  end
end
```

* `get(:name) { ... }` – runs a step returning a `Result`; on `Success` binds the
  unwrapped value to `name`, on `Failure` stops the sequence and returns it.
* `let(:name) { ... }` – binds the block's plain return value (no `Result` involved).
* `and_then { ... }` – runs a step returning a `Result` without binding its value.
* `observe { ... }` – runs a side effect; its return value is ignored.
* `and_yield { ... }` – mandatory final step; its `Result` is the value of the
  whole `in_sequence` block.

#### Complex Example in a Builder Action <a name="functional-usage-complex-action"></a>

```ruby
class Foo
  extend FunctionalLightService::Action
  expects :params
  alias :m :method

  executed do |ctx|
    Success(ctx.params) >> m(:validate) >> m(:send)
  end

  def self.validate(params)
    # do stuff
    Success(validate_and_cleansed_params)
  end

  def self.send(clean_params)
    # do stuff
    Success(result)
  end
end

class Bar
  extend FunctionalLightService::Organizer

  def self.call(params)
    with(:params => params).reduce(Foo)
  end
end

Bar.call # Success(3)
```

Chaining works with blocks (`#map` is an alias for `#>>`)

```ruby
Success(1).map {|ctx| Success(ctx + 1)}
```

it also works with lambdas

```ruby
Success(1) >> ->(ctx) { Success(ctx + 1) } >> ->(ctx) { Success(ctx + 1) }
```

and it will break the chain of execution, when it encounters a `Failure` on its way

```ruby
def works(ctx)
  Success(1)
end

def breaks(ctx)
  Failure(2)
end

def never_executed(ctx)
  Success(99)
end

Success(0) >> method(:works) >> method(:breaks) >> method(:never_executed) # Failure(2)
```

`#map` aka `#>>` will not catch any exceptions raised. If you want automatic exception handling, the `#try` aka `#>=` will catch an error and wrap it with a failure

```ruby
def error(ctx)
  raise "error #{ctx}"
end

Success(1) >= method(:error) # Failure(RuntimeError(error 1))
```

### Pattern matching <a name="functional-usage-pattern-matching"></a>

Now that you have some result, you want to control flow by providing patterns.
`#match` can match by

* success, failure, result or any
* values
* lambdas
* classes

```ruby
Success(1).match do
  Success() { |s| "success #{s}"}
  Failure() { |f| "failure #{f}"}
end # => "success 1"
```

Note1: the variant's inner value(s) have been unwrapped, and passed to the block.

Note2: only the __first__ matching pattern block will be executed, so order __can__ be important.

Note3: you can omit block parameters if you don't use them, or you can use `_` to signify that you don't care about their values. If you specify parameters, their number must match the number of values in the variant.

The result returned will be the result of the __first__ `#try` or `#let`. As a side note, `#try` is a monad, `#let` is a functor.

Guards

```ruby
Success(1).match do
  Success(where { s == 1 }) { |s| "Success #{s}" }
end # => "Success 1"
```

Note1: the guard has access to variable names defined by the block arguments.

Note2: the guard is not evaluated using the enclosing context's `self`; if you need to call methods on the enclosing scope, you must specify a receiver.

Also you can match the result class

```ruby
Success([1, 2, 3]).match do
  Success(where { s.is_a?(Array) }) { |s| s.first }
end # => 1
```

If no match was found a `NoMatchError` is raised, so make sure you always cover all possible outcomes.

```ruby
Success(1).match do
  Failure() { |f| "you'll never get me" }
end # => NoMatchError
```

Matches must be exhaustive, otherwise an error will be raised, showing the variants which have not been covered.

### Option <a name="functional-usage-option"></a>

```ruby
Some(1).some?                          # #=> true
Some(1).none?                          # #=> false
None.some?                             # #=> false
None.none?                             # #=> true
```

Maps an `Option` with the value `a` to the same `Option` with the value `b`.

```ruby
Some(1).fmap { |n| n + 1 }             # => Some(2)
None.fmap { |n| n + 1 }                # => None
```

Maps a `Result` with the value `a` to another `Result` with the value `b`.

```ruby
Some(1).map  { |n| Some(n + 1) }       # => Some(2)
Some(1).map  { |n| None }              # => None
None.map     { |n| Some(n + 1) }       # => None
```

Get the inner value or provide a default for a `None`. Calling `#value` on a `None` will raise a `NoMethodError`

```ruby
Some(1).value                          # => 1
Some(1).value_or(2)                    # => 1
None.value                             # => NoMethodError
None.value_or(0)                       # => 0
```

Add the inner values of option using `+`.

```ruby
Some(1) + Some(1)                      # => Some(2)
Some([1]) + Some(1)                    # => TypeError: No implicit conversion
None + Some(1)                         # => Some(1)
Some(1) + None                         # => Some(1)
Some([1]) + None + Some([2])           # => Some([1, 2])
```

### Coercion <a name="functional-usage-coercion"></a>

```ruby
Option.any?(nil)                       # => None
Option.any?([])                        # => None
Option.any?({})                        # => None
Option.any?(1)                         # => Some(1)

Option.some?(nil)                      # => None
Option.some?([])                       # => Some([])
Option.some?({})                       # => Some({})
Option.some?(1)                        # => Some(1)

Option.try! { 1 }                      # => Some(1)
Option.try! { raise "error"}           # => None

Some(1).match {
  Some(where { s == 1 }) { |s| s + 1 }
  Some()                 { |s| 1 }
  None()                 { 0 }
}                                      # => 2
```

### Maybe <a name="functional-usage-maybe"></a>

The simplest NullObject wrapper there can be. It adds `#some?` and `#null?` to `Object` though.

```ruby
require 'functional-light-service/functional/maybe' # you need to do this explicitly
Maybe(nil).foo        # => Null
Maybe(nil).foo.bar    # => Null
Maybe({a: 1})[:a]     # => 1

Maybe(nil).null?      # => true
Maybe({}).null?       # => false

Maybe(nil).some?      # => false
Maybe({}).some?       # => true
```

### Enums (custom ADTs) <a name="functional-usage-enum"></a>

All the above are implemented using enums, see their definition, for more details.

```ruby
Threenum = FunctionalLightService::enum {
            Nullary()
            Unary(:a)
            Binary(:a, :b)
           }

Threenum.variants                      # => [:Nullary, :Unary, :Binary]
```

Initialize

```ruby
n = Threenum.Nullary                   # => Threenum::Nullary.new()
n.value                                # => Error

u = Threenum.Unary(1)                  # => Threenum::Unary.new(1)
u.value                                # => 1

b = Threenum::Binary(2, 3)             # => Threenum::Binary(2, 3)
b.value                                # => { a:2, b: 3 }
```

Pattern matching

```ruby
Threenum::Unary(5).match {
  Nullary() {        0 }
  Unary()   { |u|    u }
  Binary()  { |a, b| a + b }
}                                      # => 5

# or
t = Threenum::Unary(5)
Threenum.match(t) {
  Nullary() {        0 }
  Unary()   { |u|    u }
  Binary()  { |a, b| a + b }
}                                      # => 5
```

If you want to return the whole matched object, you'll need to pass a reference to the object (second case). Note that `self` refers to the scope enclosing the `match` call.

```ruby
def drop(n)
  match {
    Cons(where { n > 0 }) { |h, t| t.drop(n - 1) }
    Cons()                { |_, _| self }
    Nil() { raise EmptyListError }
  }
end
```

See the linked list implementation in the specs for more examples

With guard clauses

```ruby
Threenum::Unary(5).match {
  Nullary() {     0 }
  Unary()   { |u| u }
  Binary(where { a.is_a?(Fixnum) && b.is_a?(Fixnum) }) { |a, b| a + b }
  Binary()  { |a, b| raise "Expected a, b to be numbers" }
}                                      # => 5
```

#### Add methods with impl

```ruby
FunctionalLightService::impl(Threenum) {
  def sum
    match {
      Nullary() {        0 }
      Unary()   { |u|    u }
      Binary()  { |a, b| a + b }
    }
  end

  def +(other)
    match {
      Nullary() {        other.sum }
      Unary()   { |a|    self.sum + other.sum }
      Binary()  { |a, b| self.sum + other.sum }
    }
  end
}

Threenum.Nullary + Threenum.Unary(1)   # => Unary(1)
```

All matches must be exhaustive; otherwise NoMatchError is raised.

## Usage <a name="usage"></a>

Based on the refactoring example above, just create an organizer object that calls the
actions in order and write code for the actions. That's it.

For further examples, please visit the project's [Wiki](https://github.com/sphynx79/functional-light-service/wiki).

## Upgrading to 6.0

Version 6.0 requires **Ruby >= 3.1** and ships a few breaking changes plus new guarantees.
They come from a full technical audit (see `AUDIT-functional-light-service.md`).

### Breaking changes

- **`Context#fetch` now honours the `Hash#fetch` contract**: `fetch(:missing)` without a
  default raises `KeyError` (it used to return `nil`) and fetch never writes to the
  context anymore.
- **Aliases are pure alternative names**: reads *and* writes on an alias resolve to the
  original key. `assign_aliases` no longer copies values, so `to_h` contains only the
  original keys.
- **Key collisions raise**: declaring `expects :size` (or any key that clashes with an
  existing `Hash`/`Context` method) raises `ReservedKeysInContextError` instead of
  silently returning the wrong value. Access such data via `ctx[:size]` instead.
- **`Some(nil)` raises `ArgumentError`**: absence is expressed with `None`.
- **`Context#outcome` is read-only**: use `succeed!`/`fail!` to change the outcome.
- The infrastructure keys `:_aliases`, `:_before_actions` and `:_after_actions` are
  reserved and cannot be used in `expects`/`promises`.

### New guarantees and features

- **Declarative hooks are stable**: `before_actions`/`after_actions` declared on an
  organizer now apply to *every* call (they used to disappear after the first one).
- **Rollback is complete** even when the same action class appears more than once in
  the pipeline.
- **Native pattern matching**: every enum variant supports `case/in`:

  ```ruby
  case result
  in FunctionalLightService::Result::Success[value] then value
  in FunctionalLightService::Result::Failure[error] then handle(error)
  end
  ```

  For hot paths prefer `case/in` (or `success?`/`value`) over the `match` DSL: it is
  roughly two orders of magnitude faster.
- **`skip_remaining!` is scoped**: inside `iterate`/`reduce_if`/`reduce_until` it skips
  the remaining *steps of the current sub-pipeline* (for `iterate`: of the current item),
  then the outer flow continues. The outcome message set by `skip_remaining!` is preserved.
- **Deprecations** (still working, warn once on stderr): `Maybe()`/`Null` (use
  `Option`), `Result#>=` (use `try`), `Result#<<` (use `pipe`), `Result#+`/`Option#+`.
  Silence them with `FunctionalLightService::Deprecations.silenced = true`.

### Threading contract

A `Context` is a per-call object: create it inside each organizer call (which is what
`with` does) and do not share a live context between threads. Class-level state
(hooks, aliases, logger) is read-only at call time, so calling the same organizer from
multiple threads (Puma, Sidekiq) is safe.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

Huge thanks to the [contributors](https://github.com/sphynx79/functional-light-service/graphs/contributors)!

## Changelog

Follow the changelog in this [document](https://github.com/sphynx79/functional-light-service/blob/master/CHANGELOG.md).

## Thank You

A very special thank you to [Attila Domokos](https://github.com/adomokos) for
his fantastic work on [LightService](https://github.com/adomokos/light-service).
A very special thank you to [Piotr Zolnierek](https://github.com/pzol) for
his fantastic work on [Deterministic](https://github.com/pzol/deterministic).
FunctionalLightService is inspired heavily by the concepts put to code by Attila and add some functionality taken from the excellent work of mario Piotr.

## License

FunctionalLightService is released under the [MIT License](http://www.opensource.org/licenses/MIT).
