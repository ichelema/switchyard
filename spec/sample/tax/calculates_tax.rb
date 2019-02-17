class CalculatesTax
  extend FunctionalLightService::Organizer

  def self.call(order)
    with(:order => order).reduce(
      LooksUpTaxPercentageAction,
      CalculatesOrderTaxAction,
      ProvidesFreeShippingAction
    )
  end
end
