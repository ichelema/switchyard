# FunctionalLightService
[![Gem Version](https://img.shields.io/gem/v/functional-light-service.svg)](https://rubygems.org/gems/functional-light-service)
[![CI Tests](https://github.com/sphynx79/functional-light-service/actions/workflows/project-build.yml/badge.svg)](https://github.com/sphynx79/functional-light-service/actions/workflows/project-build.yml)
[![Codecov](https://codecov.io/gh/sphynx79/functional-light-service/branch/master/graph/badge.svg)](https://app.codecov.io/gh/sphynx79/functional-light-service)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](http://opensource.org/licenses/MIT)
[![Download Count](https://ruby-gem-downloads-badge.herokuapp.com/functional-light-service?type=total)](https://rubygems.org/gems/functional-light-service)

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
		* [Complex Example in a Builder Action](#functional-usage-complex-action)
		* [Pattern matching](#functional-usage-pattern-matching)
		* [Option](#functional-usage-option)
		* [Coercion](#functional-usage-coercion)
		* [Enum](#functional-usage-enum)
		* [Maybe](#functional-usage-maybe)
* [Usage](#usage)


## Requirements

This gem requires ruby >= 2.5.0

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

While i was studying the functional programming in Ruby, i came across this fantastic gem Deterministic, that  it simplified my the writing of my Ruby code with a functional approach.
I used deterministic making extensive use of the in_sequence method, that allowed me to concatenate a series of actions in sequence, if all method that i call work nice without exception, it returned me a modad with the status Success (), in case of failure the rest of the actions was not executed, and return a monad with the status Failure ().

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

At a certain point I felt the need to better structure my code and every action had its context.
accidentally I came across  in this fantastic gem light-service, that did just what I wanted, it allows me to separate the business and logic, organize the actions in sequence, and write my actions in separate classes with each its context


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
But in this case I lost the power of functional programming that deterministic gave me, why not take the best of two world, this is the reason that brought me make this gem. Now I can use same same feature that light-service give me with the power functional programming.

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
When nothing unexpected happens during the organizer's call, the returned `context` will be successful. Here is how you can check for this:
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
However, sometimes not everything will play out as you expect it. An external API call might not be available or some complex business logic will need to stop the processing of the Series of Actions.
You have two options to stop the call chain:

1. Failing the context
2. Skipping the rest of the actions

### Failing the Context
When something goes wrong in an action and you want to halt the chain, you need to call `fail!` on the context object. This will push the context in a failure state (`context.failure? # will evalute to true`).
The context's `fail!` method can take an optional message argument, this message might help describing what went wrong.
In case you need to return immediately from the point of failure, you have to do that by calling `next context`.

In case you want to fail the context and stop the execution of the executed block, use the `fail_and_return!('something went wrong')` method.
This will immediately leave the block, you don't need to call `next context` to return from the block.

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
You can skip the rest of the actions by calling `context.skip_remaining!`. This behaves very similarly to the above-mentioned `fail!` mechanism, except this will not push the context into a failure state.
A good use case for this is executing the first couple of action and based on a check you might not need to execute the rest.
Here is an example of how you do it:
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

In the example above the organizer called 4 actions. The first 2 actions got executed successfully. The 3rd decided to skip the rest, the 4th action was not invoked. The context was successful.


## Benchmarking Actions with Around Advice
Benchmarking your action is needed when you profile the series of actions. You could add benchmarking logic to each and every action, however, that would blur the business logic you have in your actions.

Take advantage of the organizer's `around_each` method, which wraps the action calls as its reducing them in order.

Check out this example:

```ruby
class LogDuration
  def self.call(context)
    start_time = Time.now
    result = yield
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

Any object passed into `around_each` must respond to #call with two arguments: the action name and the context it will execute with. It is also passed a block, where FunctionalLightService's action execution will be done in, so the result must be returned. While this is a little work, it also gives you before and after state access to the data for any auditing and/or checks you may need to accomplish.

## Before and After Action Hooks

In case you need to inject code right before and after the actions are executed, you can use the `before_actions` and `after_actions` hooks. It accepts one or multiple lambdas that the Action implementation will invoke. This addition to FunctionalLightService is a great way to decouple instrumentation from business logic.

Consider this code:

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

The logging logic makes `TwoAction` more complex, there is more code for logging than for business logic.

You have two options to decouple instrumentation from real logic with `before_actions` and `after_actions` hooks:

1. Declare your hooks in the Organizer
2. Attach hooks to the Organizer from the outside

This is how you can declaratively add before and after hooks to the Organizer:

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

Note how the action has no logging logic after this change. Also, you can target before and after action logic for specific actions, as the `ctx.current_action` will have the class name of the currently processed action. In the example above, logging will occur only for `TwoAction` and not for `OneAction` or `ThreeAction`.

Here is how you can declaratively add `before_hooks` or `after_hooks` to your Organizer from the outside:

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
The `expects` and `promises` macros are rules for the inputs/outputs of an action.
`expects` describes what keys it needs to execute, and `promises` makes sure the keys are in the context after the
action is reduced. If either of them are violated, a custom exception is thrown.

This is how it's used:
```ruby
class FooAction
  extend FunctionalLightService::Action
  expects :baz
  promises :bar

  executed do |context|
    baz = context.fetch :baz

    bar = baz + 2
    context[:bar] = bar
  end
end
```

The `expects` macro does a bit more for you: it pulls the value with the expected key from the context, and
makes it available to you through a reader. You can refactor the action like this:

```ruby
class FooAction
  extend FunctionalLightService::Action
  expects :baz
  promises :bar

  executed do |context|
    bar = context.baz + 2
    context[:bar] = bar
  end
end
```

The `promises` macro will not only check if the context has the promised keys, it also sets it for you in the context if
you use the accessor with the same name. The code above can be further simplified:

```ruby
class FooAction
  extend FunctionalLightService::Action
  expects :baz
  promises :bar

  executed do |context|
    context.bar = context.baz + 2
  end
end
```

Take a look at [this spec](spec/action_expects_and_promises_spec.rb) to see the refactoring in action.

## Key Aliases
The `aliases` macro sets up pairs of keys and aliases in an organizer. Actions can access the context using the aliases.

This allows you to put together existing actions from different sources and have them work together without having to modify their code. Aliases will work with or without action `expects`.

Say for example you have actions `AnAction` and `AnotherAction` that you've used in previous projects.  `AnAction` provides `:my_key` but `AnotherAction` needs to use that value but expects `:key_alias`.  You can use them together in an organizer like so:

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
Enable FunctionalLightService's logging to better understand what goes on within the series of actions,
what's in the context or when an action fails.

Logging in FunctionalLightService is turned off by default. However, turning it on is simple. Add this line to your
project's config file:

```ruby
FunctionalLightService::Configuration.logger = Logger.new(STDOUT)
```

You can turn off the logger by setting it to nil or `/dev/null`.

```ruby
FunctionalLightService::Configuration.logger = Logger.new('/dev/null')
```

Watch the console while you are executing the workflow through the organizer. You should see something like this:

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

The logger logs its messages with "INFO" level. The exception to this is the event when an action fails the context.
That message is logged with "WARN" level:

```bash
I, [DATE]  INFO -- : [FunctionalLightService] - calling organizer <TestDoubles::MakesCappuccinoAddsTwoAndFails>
I, [DATE]  INFO -- : [FunctionalLightService] -     keys in context: :milk, :coffee
W, [DATE]  WARN -- : [FunctionalLightService] - :-((( <TestDoubles::MakesLatteAction> has failed...
W, [DATE]  WARN -- : [FunctionalLightService] - context message: Can't make a latte from a milk that's too hot!
```

The log message will show you what message was added to the context when the action pushed the
context into a failure state.

The event of skipping the rest of the actions is also captured by its logs:

```bash
I, [DATE]  INFO -- : [FunctionalLightService] - calling organizer <TestDoubles::MakesCappuccinoSkipsAddsTwo>
I, [DATE]  INFO -- : [FunctionalLightService] -     keys in context: :milk, :coffee
I, [DATE]  INFO -- : [FunctionalLightService] - ;-) <TestDoubles::MakesLatteAction> has decided to skip the rest of the actions
I, [DATE]  INFO -- : [FunctionalLightService] - context message: Can't make a latte with a fatty milk like that!
```

You can specify the logger on the organizer level, so the organizer does not use the global logger.

```ruby
class FooOrganizer
  extend FunctionalLightService::Organizer
  log_with Logger.new("/my/special.log")
end
```

## Error Codes
You can add some more structure to your error handling by taking advantage of error codes in the context.
Normally, when something goes wrong in your actions, you fail the process by setting the context to failure:

```ruby
class FooAction
  extend FunctionalLightService::Action

  executed do |context|
    context.fail!("I don't like what happened here.")
  end
end
```

However, you might need to handle the errors coming from your action pipeline differently.
Using an error code can help you check what type of expected error occurred in the organizer
or in the actions.

```ruby
class FooAction
  extend FunctionalLightService::Action

  executed do |context|
    unless (service_call.success?)
      context.fail!("Service call failed", error_code: 1001)
    end

    # Do something else

    unless (entity.save)
      context.fail!("Saving the entity failed", error_code: 2001)
    end
  end
end
```

## Action Rollback
Sometimes your action has to undo what it did when an error occurs. Think about a chain of actions where you need
to persist records in your data store in one action and you have to call an external service in the next. What happens if there
is an error when you call the external service? You want to remove the records you previously saved. You can do it now with
the `rolled_back` macro.

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

You need to call the `fail_with_rollback!` method to initiate a rollback for actions starting with the action where the failure
was triggered.

```ruby
class CallExternalApi
  extend FunctionalLightService::Action

  executed do |context|
    api_call_result = SomeAPI.save_user(context.user)

    context.fail_with_rollback!("Error when calling external API") if api_call_result.failure?
  end
end
```

Using the `rolled_back` macro is optional for the actions in the chain. You shouldn't care about undoing non-persisted changes.

The actions are rolled back in reversed order from the point of failure starting with the action that triggered it.

See [this](spec/acceptance/rollback_spec.rb) acceptance test to learn more about this functionality.

## Localizing Messages
By default FunctionalLightService provides a mechanism for easily translating your error or success messages via I18n.  You can also provide your own custom localization adapter if your application's logic is more complex than what is shown here.

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

This also works with nested classes via the ActiveSupport `#underscore` method, just as ActiveRecord performs localization lookups on models placed inside a module.

```ruby
module PaymentGateway
  class CaptureFunds
    extend FunctionalLightService::Action

    executed do |context|
      if api_service.failed?
        context.fail!(:funds_not_available)
      end

      # this failure message equates to:
      # I18n.t(:funds_not_available, scope: "payment_gateway/capture_funds.light_service.failures")
    end
  end
end
```

If you need to provide custom variables for interpolation during localization, pass that along in a hash.

```ruby
module PaymentGateway
  class CaptureFunds
    extend FunctionalLightService::Action

    executed do |context|
      if api_service.failed?
        context.fail!(:funds_not_available, last_four: "1234")
      end

      # this failure message equates to:
      # I18n.t(:funds_not_available, last_four: "1234", scope: "payment_gateway/capture_funds.light_service.failures")

      # the translation string itself being:
      # => "Unable to process your payment for account ending in %{last_four}"
    end
  end
end
```

To provide your own custom adapter, use the configuration setting and subclass the default adapter FunctionalLightService provides.

```ruby
FunctionalLightService::Configuration.localization_adapter = MyLocalizer.new

# lib/my_localizer.rb
class MyLocalizer < FunctionalLightService::LocalizationAdapter

  # I just want to change the default lookup path
  # => "light_service.failures.payment_gateway/capture_funds"
  def i18n_scope_from_class(action_class, type)
    "light_service.#{type.pluralize}.#{action_class.name.underscore}"
  end
end
```

To get the value of a `fail!` or `succeed!` message, simply call `#message` on the returned context.

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

The `FunctionalLightService::Context` is initialized with the first action, that context is passed around among organizers and actions. This code is still simpler than many out there, but it feels very imperative: it has conditionals, iterators in it. Let's see how we could make it a bit more simpler with a declarative style:

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

This code is much easier to reason about, it's less noisy and it captures the goal of FunctionalLightService well: simple, declarative code that's easy to understand.

The 7 different constructs an organizer can have:

1. `reduce_until`
2. `reduce_if`
3. `iterate`
4. `execute`
5. `with_callback`
6. `add_to_context`
7. `add_aliases`

`reduce_until` behaves like a while loop in imperative languages, it iterates until the provided predicate in the lambda evaluates to true. Take a look at [this acceptance test](spec/acceptance/organizer/reduce_until_spec.rb) to see how it's used.

`reduce_if` will reduce the included organizers and/or actions if the predicate in the lambda evaluates to true. [This acceptance test](spec/acceptance/organizer/reduce_if_spec.rb) describes this functionality.

`iterate` gives your iteration logic, the symbol you define there has to be in the context as a key. For example, to iterate over items you will use `iterate(:items)` in your steps, the context needs to have `items` as a key, otherwise it will fail. The organizer will singularize the collection name and will put the actual item into the context under that name. Remaining with the example above, each element will be accessible by the name `item` for the actions in the `iterate` steps. [This acceptance test](spec/acceptance/organizer/iterate_spec.rb) should provide you with an example.

To take advantage of another organizer or action, you might need to tweak the context a bit. Let's say you have a hash, and you need to iterate over its values in a series of action. To alter the context and have the values assigned into a variable, you need to create a new action with 1 line of code in it. That seems a lot of ceremony for a simple change. You can do that in a `execute` method like this `execute(->(ctx) { ctx[:some_values] = ctx.some_hash.values })`. [This test](spec/acceptance/organizer/execute_spec.rb) describes how you can use it.

Use `with_callback` when you want to execute actions with a deferred and controlled callback. It works similar to a Sax parser, I've used it for processing large files. The advantage of it is not having to keep large amount of data in memory. See [this acceptance test](spec/acceptance/organizer/with_callback_spec.rb) as a working example.

`add_to_context` can add key-value pairs on the fly to the context. This functionality is useful when you need a value injected into the context under a specific key right before the subsequent actions are executed. [This test](spec/acceptance/organizer/add_to_context_spec.rb) describes its functionality.

Your action needs a certain key in the context but it's under a different one? Use the function `add_aliases` to alias an existing key in the context under the desired key. Take a look at [this test](spec/acceptance/organizer/add_aliases_spec.rb) to see an example.

## ContextFactory for Faster Action Testing

As the complexity of your workflow increases, you will find yourself spending more and more time creating a context (FunctionalLightService::Context it is) for your action tests. Some of this code can be reused by clever factories, but still, you are using a context that is artificial, and can be different from what the previous actions produced. This is especially true, when you use FunctionalLightService in ETLs, where you start out with initial data and your actions are mutating its state.

Here is an example:

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

In order to test the third action `ETL::SetsUpMappingAction`, you have to have several entities in the context. Depending on the logic you need to write code for, this could be a lot of work. However, by using the `ContextFactory` in your spec, you could easily have a prepared context that’s ready for testing:

```ruby
require 'spec_helper'
require 'light-service/testing'

RSpec.describe ETL::SetsUpMappingsAction do
  let(:context) do
    FunctionalLightService::Testing::ContextFactory
      .make_from(SomeOrganizer)
      .for(described_class)
      .with(:payload => File.read(‘spec/data/payload.json’)
  end

  it ‘works like it should’ do
    result = described_class.execute(context)
    expect(result).to be_success
  end
end
```

This context then can be passed to the action under test, freeing you up from the 20 lines of factory or fixture calls to create a context for your specs.

In case your organizer has more logic in its `call` method, you could create your own test organizer in your specs like you can see it in this [acceptance test](spec/acceptance/testing/context_factory_spec.rb#L4-L11). This is reusable in all your action tests.

## Functional programming
FunctionalLightService is to help your code to be more confident, by utilizing functional programming patterns.

## Patterns
FunctionalLightService provides different monads, here is a short guide, when to use which

#### Result: Success & Failure
- an operation which can succeed or fail
- the result (content) of of the success or failure is important
- you are building one thing
- chaining: if one fails (Failure), don't execute the rest

#### Option: Some & None
- an operation which returns either some result or nothing
- in case it returns nothing it is not important to know why
- you are working rather with a collection of things
- chaining: execute all and then select the successful ones (Some)


#### Maybe
- an object may be nil, you want to avoid endless nil? checks

#### Enums (Algebraic Data Types)
- roll your own pattern

## Usage <a name="functional-usage"></a>
### Result: Success & Failure <a name="functional-usage-success-failure"></a>

```ruby
Success(1).to_s                        # => "1"
Success(Success(1))                    # => Success(1)

Failure(1).to_s                        # => "1"
Failure(Failure(1))                    # => Failure(1)
```

Maps a `Result` with the value `a` to the same `Result` with the value `b`.

```ruby
Success(1).fmap { |v| v + 1}           # => Success(2)
Failure(1).fmap { |v| v - 1}           # => Failure(0)
```

Maps a `Result` with the value `a` to another `Result` with the value `b`.

```ruby
Success(1).bind { |v| Failure(v + 1) } # => Failure(2)
Failure(1).bind { |v| Success(v - 1) } # => Success(0)
```

Maps a `Success` with the value `a` to another `Result` with the value `b`. It works like `#bind` but only on `Success`.

```ruby
Success(1).map { |n| Success(n + 1) }  # => Success(2)
Failure(0).map { |n| Success(n + 1) }  # => Failure(0)
```
Maps a `Failure` with the value `a` to another `Result` with the value `b`. It works like `#bind` but only on `Failure`.

```ruby
Failure(1).map_err { |n| Success(n + 1) } # => Success(2)
Success(0).map_err { |n| Success(n + 1) } # => Success(0)
```

```ruby
Success(0).try { |n| raise "Error" }   # => Failure(Error)
```

Replaces `Success a` with `Result b`. If a `Failure` is passed as argument, it is ignored.

```ruby
Success(1).and Success(2)              # => Success(2)
Failure(1).and Success(2)              # => Failure(1)
```

Replaces `Success a` with the result of the block. If a `Failure` is passed as argument, it is ignored.

```ruby
Success(1).and_then { Success(2) }     # => Success(2)
Failure(1).and_then { Success(2) }     # => Failure(1)
```

Replaces `Failure a` with `Result`. If a `Failure` is passed as argument, it is ignored.

```ruby
Success(1).or Success(2)               # => Success(1)
Failure(1).or Success(1)               # => Success(1)
```

Replaces `Failure a` with the result of the block. If a `Success` is passed as argument, it is ignored.

```ruby
Success(1).or_else { Success(2) }      # => Success(1)
Failure(1).or_else { |n| Success(n)}   # => Success(1)
```

Executes the block passed, but completely ignores its result. If an error is raised within the block it will **NOT** be catched.

Try failable operations to return `Success` or `Failure`

```ruby
include FunctionalLightService::Prelude::Result

try! { 1 }                             # => Success(1)
try! { raise "hell" }                  # => Failure(#<RuntimeError: hell>)
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

### Enums <a name="functional-usage-enum"></a>
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

Implementing methods for enums

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

All matches must be exhaustive, i.e. cover all variants

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

## Usage <a name="usage"></a>
Based on the refactoring example above, just create an organizer object that calls the
actions in order and write code for the actions. That's it.

For further examples, please visit the project's [Wiki](https://github.com/sphynx79/functional-light-service/wiki).

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
