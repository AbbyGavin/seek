class AssayMeasurement < ApplicationRecord
  belongs_to :assay, inverse_of: :assay_measurements
  belongs_to :measurement, inverse_of: :assay_measurements

  validates_presence_of :assay
  validates_presence_of :measurement

  include Seek::Rdf::ReactToAssociatedChange
  update_rdf_on_change :assay
end

