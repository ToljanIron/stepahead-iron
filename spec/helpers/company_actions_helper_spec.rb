require 'spec_helper'
require 'rails_helper'

describe CompanyActionsHelper, type: :helper do
  let(:logo) { fixture_file_upload(Rails.root.join('spec', 'fixtures', 'test_image.jpg'), 'image/jpeg') }
  let(:logo_wrong_extension) { fixture_file_upload(Rails.root.join('spec', 'fixtures', 'test_image.svg'), 'image/jpeg') }
  let(:company) { Company.create!(id: 1, name: 'Comp') }

  describe '#upload_company_logo' do
    it 'Wrong logo extension' do
      result = CompanyActionsHelper.upload_company_logo(logo_wrong_extension, company)

      expect(result).to eq('Logo suffix should be one of: .jpg or .png')
    end

    it 'Upload logo successfully to AWS S3' do
      result = CompanyActionsHelper.upload_company_logo(logo, company)
      
      expect(result).to be_nil
      expect(company.logo_url).to_not be_nil
    end
  end
end
