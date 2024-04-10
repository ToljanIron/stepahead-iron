require 'spec_helper'
include SessionsHelper

describe CompaniesController, type: :controller do
  before do
    Company.create(id: 1, name: 'Comp')
  end

  describe 'logo_upload' do
    let(:logo) { fixture_file_upload(Rails.root.join('spec', 'fixtures', 'test_image.jpg'), 'image/jpeg') }

    it 'Upload logo successfully' do
      tmp = http_post_with_jwt_token(:logo_upload, {id: 1, logo: logo})
      res = JSON.parse tmp.body
      
      expect(res["success"]).to eq(true)
      expect(res["logo"]).to eq('test_image.jpg')
    end

    it 'Upload logo fail with wrong company' do
      tmp = http_post_with_jwt_token(:logo_upload, {id: 2, logo: logo})
      res = JSON.parse tmp.body

      expect(res["success"]).to eq(false)
      expect(res["error"][0]).to eq('No company with the id: 2')
    end
  end

  describe 'logo_remove' do
    it 'Remove logo successfully' do
      tmp = http_post_with_jwt_token(:logo_remove, {id: 1})
      res = JSON.parse tmp.body

      expect(res["success"]).to eq(true)
    end

    it 'Remove logo fail with wrong company' do
      tmp = http_post_with_jwt_token(:logo_remove, {id: 2})
      res = JSON.parse tmp.body
      
      expect(res["success"]).to eq(false)
      expect(res["error"][0]).to eq('No company with the id: 2')
    end
  end
end
