module MeasurementsHelper

  def can_create_measurements?
    Measurement.can_create?
  end
end

