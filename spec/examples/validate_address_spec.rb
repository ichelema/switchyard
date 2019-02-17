require 'spec_helper'

# A Unit of Work for validating an address
module ValidateAddress
  extend FunctionalLightService::Prelude::Result

  def self.call(candidate)
    errors = {}
    errors[:street] = "Street cannot be empty" unless candidate.key? :street
    errors[:city]   = "Street cannot be empty" unless candidate.key? :city
    errors[:postal] = "Street cannot be empty" unless candidate.key? :postal

    errors.empty? ? Success(candidate) : Failure(errors)
  end
end

describe ValidateAddress do
  include FunctionalLightService
  subject { ValidateAddress.call(candidate) }
  context 'sunny day' do
    let(:candidate) do
      { :title => "Hobbiton",
        :street => "501 Buckland Rd",
        :city => "Matamata",
        :postal => "3472",
        :country => "nz" }
    end
    specify { expect(subject).to be_a FunctionalLightService::Result::Success }
    specify { expect(subject.value).to eq candidate }
  end

  context 'empty data' do
    let(:candidate) { {} }
    specify { expect(subject).to be_a FunctionalLightService::Result::Failure }
    specify { expect(subject.value).to include(:street, :city, :postal) }
  end
end
