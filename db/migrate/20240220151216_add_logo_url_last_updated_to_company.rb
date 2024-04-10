class AddLogoUrlLastUpdatedToCompany < ActiveRecord::Migration[6.1]
  def change
    add_column :companies, :logo_url_last_updated, :datetime, default: 1.day.ago
  end
end
