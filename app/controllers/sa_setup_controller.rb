require 'oj'
require 'oj_mimic_json'

include ImportDataHelper
include SftpHelper

class SaSetupController < ActionController::Base

  before_action :init_conf

  def base
    redirect_if_needed
  end

  def microsoft_auth
    Company.last.update(setup_state: :microsoft_auth)
  end

  def microsoft_auth_redirect
    url = get_redirect_auth_path
    redirect_to url
  end

  def microsoft_auth_back
    Company.last.update(setup_state: :upload_company)
    write_tenant_to_conf(params)
    redirect_if_needed
  end

  def log_files_location
    redirect_if_needed
    Company.last.update(setup_state: :log_files_location)
    @host = CompanyConfigurationTable.find_by(key: 'COLLECTOR_TRNAS_HOST', comp_id: -1).value
    @user = CompanyConfigurationTable.find_by(key: 'COLLECTOR_TRNAS_USER', comp_id: -1).value
    @dir  = CompanyConfigurationTable.find_by(key: 'COLLECTOR_TRNAS_SRC_DIR', comp_id: -1).value
    puts "in log_files_location"
  end

  def log_files_location_set
    puts "in log_files_location_set"
    Company.last.update(setup_state: :log_files_location_verification)
    params.permit(:sftpHost, :sftpUser, :sftpPassword, :sftpLogsDir)

    host = params[:sftpHost].sanitize_url
    if host.nil?
      redirect_to_error("Bad value for host name: #{params[:sftpHost]}")
      return
    end

    user = params[:sftpUser].sanitize_is_alphanumeric
    if user.nil?
      redirect_to_error("Bad value for username: #{params[:sftpUser]}")
      return
    end

    pass = params[:sftpPassword].sanitize_is_alphanumeric
    if pass.nil?
      redirect_to_error("Bad value for password: #{params[:sftpPassword]}")
      return
    end

    logs_dir = params[:sftpLogsDir].sanitize_is_alphanumeric
    if pass.nil?
      redirect_to_error("Bad value for log files directory: #{params[:sftpLogsDir]}")
      return
    end

    CompanyConfigurationTable.find_by(
      key: 'COLLECTOR_TRNAS_HOST',
      comp_id: -1
    ).update(value: host)
    CompanyConfigurationTable.find_by(
      key: 'COLLECTOR_TRNAS_USER',
      comp_id: -1
    ).update(value: user)
    CompanyConfigurationTable.find_by(
      key: 'COLLECTOR_TRNAS_PASSWORD',
      comp_id: -1
    ).update(value: CdsUtilHelper.encrypt(pass))
    CompanyConfigurationTable.find_by(
      key: 'COLLECTOR_TRNAS_SRC_DIR',
      comp_id: -1
    ).update(value: logs_dir)

    trans_type = CompanyConfigurationTable.find_by(
      key: 'COLLECTOR_TRNAS_TYPE',
      comp_id: -1
    ).value

    begin
      if trans_type == 'SFTP'
        SftpHelper.sftp_copy(host, user, pass, '*.log', logs_dir, '/tmp')
      end
    rescue => ex
      error = translate_sftp_error(ex.message)
      msg = "SFTP server error: #{error}"
      puts msg
      EventLog.create(message: msg)
      puts ex.backtrace
      Company.last.update(setup_state: :log_files_location)
      redirect_to_error(msg)
      return
    end

    Company.last.update(setup_state: :gpg_passphrase)
    redirect_to controller: 'sa_setup', action: 'base'
  end

  def gpg_passphrase
    redirect_if_needed
    puts "in gpg_passphrase"
  end

  def gpg_passphrase_set
    puts "in gpg_passphrase"
    params.permit(:gpgPassphrase)

    gpgpass = params[:gpgPassphrase].sanitize_is_alphanumeric
    if gpgpass.nil?
      redirect_to_error("Bad GPG passphrase: #{params[:gpgPassphrase]}")
      return
    end

    CompanyConfigurationTable.find_by(
      key: 'COLLECTOR_DECRYPTION_PASSPHRASE',
      comp_id: -1
    ).update( value: CdsUtilHelper.encrypt(gpgpass) )

    Company.last.update(setup_state: :upload_company)
    redirect_to controller: 'sa_setup', action: 'base'
  end

  def upload_company
    puts "in upload_company"
    if Employee.count > 0
      Company.last.update(setup_state: :standby_or_push)
      redirect_to controller: 'sa_setup', action: 'base'
      return
    end
  end

  def employees_excel
    puts "Uploading employees_excel"
    params.permit(:empsExcel)
    emps_file = params[:empsExcel][:file]

    begin
      load_excel_sheet(1, emps_file, 1, true)
    rescue RuntimeError => ex
      msg = "Exception while loading employees: #{ex.message}"
      puts msg
      EventLog.create(message: msg)
      puts ex.backtrace
      redirect_to_error("Upload errors: #{errors}")
      return
    end

    Company.last.update(setup_state: :standby_or_push)
    redirect_to controller: 'sa_setup', action: 'base'
  end

  def standby_or_push
    puts "in standby_or_push"
  end

  def goto_system
    puts "in goto_system"
    Company.last.update(setup_state: :ready)
    redirect_to "https://stepahead.2stepahead.com"
  end

  def collect_now
    puts "in collect_now"
    Company.last.update(setup_state: :push)
    Delayed::Job.enqueue(
      HistoricalDataJob.new,
      queue: 'collector_queue',
      run_at: 5.hours.ago
    )
    redirect_to controller: 'sa_setup', action: 'base'
  end

  def push
    puts "in push"
  end

  def collect_again
    puts "in retry push"
    Company.last.update(setup_state: :push)
    PushProc.delete_all
    Logfile.delete_all
    PushProc.create(company_id: Company.last.id)
    Delayed::Job.enqueue(
      HistoricalDataJob.new,
      queue: 'collector_queue',
      run_at: 5.hours.ago
    )
    redirect_to controller: 'sa_setup', action: 'base'
  end

  def get_push_state
    puts "In get_push_state"
    job = Company.last.jobs.where("domain_id like '%historical-data%'").last
    ret = {}
    if job.nil?
      ret = { status: 'ok', percent_complete: 0.0 }
    elsif job.status == 'done'
      ret = { status: 'done', percent_complete: 100.0 }
    else
      ret = {
        status: job.status == 'error' ? 'error' : 'ok',
        error_msg: job.error_message,
        percent_complete: job.percent_complete
      }
    end
    render json: Oj.dump( ret ), status: 200
  end

  def form_error
    params.permit(:error_msg)
    @error_msg = params[:error_msg]
  end

  private

  def redirect_to_error(msg)
    redirect_to controller: 'sa_setup', action: 'form_error', error_msg: msg
  end

  def redirect_if_needed
    curr_action = params[:action]
    setup_state = Company.last.setup_state

    @conf.get_collector_type
    case setup_state
    when 'init'
      if @conf.get_collector_type == 'Office365'
        redirect_to controller: 'sa_setup', action: 'microsoft_auth' unless curr_action == 'microsoft_auth'
      elsif @conf.get_collector_type == 'Exchange'
        redirect_to controller: 'sa_setup', action: 'log_files_location' unless curr_action == 'log_files_location'
      end
    when 'microsoft_auth'
      redirect_to controller: 'sa_setup', action: 'microsoft_auth' unless curr_action == 'microsoft_auth'
    when 'log_files_location'
      redirect_to controller: 'sa_setup', action: 'log_files_location' unless curr_action == 'log_files_location'
    when 'log_files_location_verification'
      redirect_to controller: 'sa_setup', action: 'log_files_location_verification' unless curr_action == 'log_files_location_verification'
    when 'gpg_passphrase'
      redirect_to controller: 'sa_setup', action: 'gpg_passphrase' unless curr_action == 'gpg_passphrase'
    when 'upload_company'
      redirect_to controller: 'sa_setup', action: 'upload_company' unless curr_action == 'upload_company'
    when 'standby_or_push'
      redirect_to controller: 'sa_setup', action: 'standby_or_push' unless curr_action == 'standby_or_push'
    when 'goto_system'
      redirect_to controller: 'sa_setup', action: 'goto_system' unless curr_action == 'goto_system'
    when 'collect_now'
      redirect_to controller: 'sa_setup', action: 'collect_now' unless curr_action == 'collect_now'
    when 'push'
      redirect_to controller: 'sa_setup', action: 'push' unless curr_action == 'push'
    when 'it_done'
      redirect_to controller: 'sa_setup', action: 'it_done' unless curr_action == 'it_done'
    else
      raise "Illegal setup_state: #{setup_state}"
    end
  end

  def translate_sftp_error(msg)
    return "Unknown error" if msg.nil?
    return "Unknown host" if msg.include?('Name or service not known')
    return "Authentication failed" if msg.include?('Authentication failed')
    return "No such file or directory" if msg.include?('no such file')
    return "Unknown error: #{msg}"
  end

  def init_conf
    @conf = CompanyConfigurationTable.new
  end

  #############################################################################
  ## Get a URL to login to office365. It will look something like this:
  ##
  ## url = 'https://login.microsoftonline.com/common/adminconsent?' +
  ## '&client_id=75a31645-f694-4368-a42a-fa5c56532077' +
  ## '&state=btx4jv7FFaFTj9ukKjDA' +
  ## '&redirect_uri=https://dev.spectory.com:3000/app_redirect'
  ##
  #############################################################################
  def get_redirect_auth_path
    url = 'https://login.microsoftonline.com/common/adminconsent?' +
    '&client_id='+ @conf.get_collector_o365_client_id +
    '&state=' + @conf.get_collector_o365_redirect_state +
    '&redirect_uri=' + @conf.get_collector_o365_redirect_uri

    return url
  end

  def write_tenant_to_conf(params)
    state = params['state']
    raise "Did not identify origin of reply from Microsoft" if state != @conf.get_collector_o365_redirect_state
    tenant = params['tenant']
    CompanyConfigurationTable.find_by(key: 'COLLECTOR_O365_TENANT_ID', comp_id: -1).update(value: tenant)
  end
end
