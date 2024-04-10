class CompaniesController < ApiController
  def update
    authorize :company, :index?
    id = params[:company][:id].to_i if params[:company]
    name = params[:company][:name] if params[:company]
    comp = Company.find(id) if id
    comp.update_attribute(:name, name) if name
    redirect_to admin_page_path
  end

  def logo_upload
    err = []
    success = false

    begin
      company = Company.find(params[:id])
      logo = params[:logo]
      result = CompanyActionsHelper.upload_company_logo(logo, company)

      if result.nil?
        success = true
      else
        err << result
      end
    rescue => e
      err << "No company with the id: #{params[:id]}"
    end

    render json: {logo: company.logo_url, success: success, error: err}
  end

  def logo_remove
    err = []
    success = false

    begin
      company = Company.find(params[:id])
      company.update!(
        logo_url: '',
        logo_url_last_updated: Time.now
      )

      success = true
    rescue => e
      err << "No company with the id: #{params[:id]}"
    end

    render json: {success: success, error: err}
  end
end
