class Role < ActiveRecord::Base
  has_many :employees
  belongs_to  :company
  belongs_to :color

  validates :company_id, presence: true
  validates :name, presence: true, length: { maximum: 100 }
  validates :name, uniqueness: { scope: :company_id, message: 'should be unique per company' }

  before_save do
    if color_id.nil?
      self.color_id = rand(24 + 1)
    end
  end

  def pack_to_json
    h = {}
    h[:name] = name
    h[:color] = color.rgb
    return h
  end
end
