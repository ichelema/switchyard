require 'spec_helper'
require 'pry'

module FunctionalLightService
  module Currify
    module ClassMethods
      def currify(*names)
        names.each do |name|
          unbound_method = instance_method(name)

          define_method(name) do |*args|
            curried_method = unbound_method.bind(self).to_proc.curry
            curried_method[*args]
          end
        end
      end
    end

    def self.included(curried)
      curried.extend ClassMethods
    end
  end
end

class Object
  class Proc
    def self.compose(f, g)
      ->(*args) { f[g[*args]] }
    end

    # rubocop:disable Naming/BinaryOperatorParameterName
    # Compose left to right
    def |(g)
      Proc.compose(g, self)
    end

    # Compose right to left
    def *(g)
      Proc.compose(self, g)
    end
    # rubocop:enable Naming/BinaryOperatorParameterName
  end
end

class Booking
  include FunctionalLightService::Currify
  include FunctionalLightService::Prelude::Result

  def initialize(deps)
    @deps = deps
  end

  def build(id, format)
    validate(id) | req | find | render(format)

    validate(id) | request(id) | find
  end

  def validate(id)
    Success(id)
  end

  def req(a, id)
    Success(:id => id + a)
  end

  def find(req)
    Success(:found => req)
  end

  def render(format, req)
    Success("rendered in #{format}: #{req[:found]}")
  end

  currify :find, :render, :req
end

describe "Pref" do
  include FunctionalLightService::Prelude::Result

  it "does something" do
    b = Booking.new(1)
    actual = b.validate(1) >> b.req(2) >> b.find >> b.render(:html)

    expected = FunctionalLightService::Result::Success.new("rendered in html: {:id=>3}")
    expect(actual).to eq expected
  end
end
