require 'spec_helper'

describe "native Ruby pattern matching (case/in) support" do
  include FunctionalLightService::Prelude::Result
  include FunctionalLightService::Prelude::Option

  Result = FunctionalLightService::Result
  Option = FunctionalLightService::Option

  it "deconstructs Success/Failure positionally" do
    matched =
      case Success(42)
      in Result::Success[value] then "success: #{value}"
      in Result::Failure[error] then "failure: #{error}"
      end

    expect(matched).to eq("success: 42")
  end

  it "deconstructs Failure positionally" do
    matched =
      case Failure(:boom)
      in Result::Success[value] then "success: #{value}"
      in Result::Failure[error] then "failure: #{error}"
      end

    expect(matched).to eq("failure: boom")
  end

  it "deconstructs by keys using the variant's field names" do
    matched =
      case Success(42)
      in Result::Success(s:) then s
      in Result::Failure(f:) then f
      end

    expect(matched).to eq(42)
  end

  it "deconstructs Some and None" do
    some_result =
      case Some(7)
      in Option::Some[v] then v
      in Option::None then :none
      end
    none_result =
      case None()
      in Option::Some[v] then v
      in Option::None then :none
      end

    expect(some_result).to eq(7)
    expect(none_result).to eq(:none)
  end

  Shape = FunctionalLightService.enum do
    Point(:x, :y)
    Origin()
  end

  it "deconstructs multi-field (Binary) variants by keys" do
    matched =
      case Shape::Point.new(1, 2)
      in Shape::Point(x:, y:) then [x, y]
      in Shape::Origin then [0, 0]
      end

    expect(matched).to eq([1, 2])
  end

  def None
    FunctionalLightService::Option::None.new
  end
end
