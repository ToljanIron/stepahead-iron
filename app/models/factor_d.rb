class FactorD < ApplicationRecord
    has_many :employees
    belongs_to :company
end
