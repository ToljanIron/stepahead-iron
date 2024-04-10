require 'line_processing_context.rb'
require 'csv'
#require 'roo'

module ImportDataHelper
  #
  # accepts the company_id of the company in question
  # and a csv string with lines describing company
  # structure, personal info or management structure
  #
  # creates and/or connects the objects in the database
  #
  # returns an array of string error messages
  #
  EMPLOYEES_CSV  = 1
  MANAGMENT_RELATION_CSV = 3
  NETWORK        = 4
  EMAILS         = 5
  GROUPS_CSV     = 6

  CSV_NAMES = [
    'NA',
    'Employees',
    'NA',
    'Management',
    'Network',
    'Emails',
    'Groups'
  ]

  CSV_TYPES = {
    employee_csv: EMPLOYEES_CSV,
    managment_relation_csv: MANAGMENT_RELATION_CSV,
    trust: NETWORK,
    emails: EMAILS,
    groups_csv: GROUPS_CSV
  }

  VALID_GROUP_CSV_LINE_SIZE      = 5
  VALID_MANAGMENT_RELATION_CSV_LINE_SIZE = 4
  VALID_EMPLOYEE_CSV_LINE_SIZE   = 20
  VALID_EMPLOYEE_CSV_LINE_SIZE_LEAN = 21
  VALID_NETWORK_CSV_LINE_SIZE    = 4
  VALID_EMAILS_CSV_LINE_SIZE     = 20


  def push_errors(errors, company_id, file, network, csv_type, use_latest_snapshot=false, date_format = nil)
    errors.push '-' * 50 + "\n#{network.name}:\n"        if csv_type == NETWORK
    errors.push '-' * 50 + "\n#{CSV_NAMES[csv_type]}:\n" if csv_type != NETWORK

    errors.push ImportDataHelper.import_data_from_csv_to_db(company_id, file.read, network, csv_type, use_latest_snapshot, date_format) if file
  end

  ######################### Imange upload #########################################
  IMAGES_FILE_NAME='/home/dev/Development/workships/public/employee_images.zip'
  def upload_images(cid, images_file)
    puts "Saving uploaded employees zip file for company: #{cid}"
    File.open(IMAGES_FILE_NAME, "wb") { |f| f.write(images_file.read) }
    puts "Done"
  end

 def validate_unverified_by_excel_sheet(cid,spreadsheet,sid)
  ex = Roo::Excelx.new(spreadsheet.path)
  emps_sht = ex.sheet('Employees')

  context_list = lift_excel_to_context_list(cid, emps_sht, 'emps', sid)
  
  context_list.each do |co|
    #ii += 1
    #puts "Working on context number: #{ii}" if (ii % 50 == 0)
    
    
    if co.attrs[:delete]
      puts "111111111111111111"
      puts(co.attrs)
      emp=Employee.where(email:co.attrs[:email]).first
      if(emp)
        qp=QuestionnaireParticipant.where(employee:emp).first
        qp.destroy!
        emp.destroy!
      end
   else
      puts "222222222222222222"
      co.validate_employee
      #id = co.connect
      #eids << id if co.class == EmployeeLineProcessingContext
    end
  end
    
 end

 def merge_employees_by_excel_sheet(cid, spreadsheet, sid)
  ex = Roo::Excelx.new(spreadsheet.path)
  emps_sht = ex.sheet('Employees')

  context_list = lift_excel_to_context_list(cid, emps_sht, 'emps', sid)

  context_list.each do |co|
    next if co.attrs[:merge].to_s.empty?
    
    begin
      merge_from_emp = Employee.find_by(id: co.attrs[:existing_id])
      next unless merge_from_emp
      
      q = Questionnaire.find_by(snapshot_id: co.attrs[:snapshot_id])
      merge_from_qp = QuestionnaireParticipant.find_by(employee_id: merge_from_emp.id)
      merge_into_emp = Employee.find_by(company_id: merge_from_emp.company_id, external_id: co.attrs[:merge], snapshot_id: sid)
      next unless merge_into_emp && merge_from_qp

      merge_into_qp = QuestionnaireParticipant.find_or_create_by(questionnaire: q, employee: merge_into_emp)
      
      QuestionReply.where(questionnaire_id: q.id, reffered_questionnaire_participant_id: merge_from_qp.id).find_each do |qr|
        qr.update!(reffered_questionnaire_participant_id: merge_into_qp.id)
      end

      # Cleanup
      merge_from_qp.destroy
      merge_from_emp.destroy

    rescue => e
      puts "Merge failed for employee #{co.attrs[:existing_id]} -> external id #{co.attrs[:merge]}: #{e}"
      next
    end
  end
end
  ######################### Import Excel  #########################################

  ## This loader can use two formats, one full, with 20 fields, and the other
  ## lean with only 11.
  def load_excel_sheet(cid, spreadsheet, sid, lean=false,include_groups=true)
    
    context_list=[]
    ex = Roo::Excelx.new(spreadsheet.path)
    if (include_groups)
      groups_sht = ex.sheet('Groups')
      groups_context_list = lift_excel_to_context_list(cid, groups_sht, 'groups', sid, lean)
      context_list = groups_context_list
      ## This is not a mistake. It's done in order to make sure all group parent groups are accounted for
      context_list += groups_context_list
    end
    emps_sht = ex.sheet('Employees')
    context_list += lift_excel_to_context_list(cid, emps_sht, 'emps', sid, lean)

    ii = 0
    eids = []
    context_list.each do |co|
      ii += 1
      puts "Working on context number: #{ii}" if (ii % 50 == 0)
      #Rails.logger.info([co.attrs[:email],co.attrs[:delete]].join(','))

      if co.attrs[:delete]
        puts "111111111111111111"
        puts(co.attrs)
        emp=Employee.where(email:co.attrs[:email]).first
        if emp
          qp=QuestionnaireParticipant.where(employee:emp).first
          qp.destroy!
          emp.destroy!
        end
      else
        puts "222222222222222222"
        co.create_if_not_existing
        id = co.connect
        eids << id if co.class == EmployeeLineProcessingContext
      end
    end
    if (include_groups)
      Group.prepare_groups_for_hierarchy_queries(sid)
    end
    errors = context_list_errors(context_list)
    return [eids, errors]
  end

  def lift_excel_to_context_list(cid, xls, sht_type, sid, lean=true)
    context_list = xls.each_with_index.map do |xls_line, xls_line_number|
      ret = nil
      if xls_line_number > 0
        ret = process_xls_employee(xls_line, cid, xls_line, xls_line_number, sid, lean) if sht_type == 'emps'
        ret = process_xls_groups(xls_line, cid, xls_line, xls_line_number, sid, lean) if sht_type == 'groups'
      end
      ret
    end
    ret = context_list.flatten
    ret = ret.select { |e| !e.nil? }
    return ret
  end

  def parse_date_for_xls(d)
    return nil if d.nil?
    return nil if d.class == String
    return d.strftime("%Y-%m-%d")
  end

  def process_xls_employee(parsed, company_id, csv_line, csv_line_number, sid, lean)

    if !lean
      puts "Warning: Line size: #{parsed.length} is incorrect for line number: #{csv_line_number},
      should be #{VALID_EMPLOYEE_CSV_LINE_SIZE} - will proceed anyway.\n*This warning can heppen also
      when there are empty cells at the end of each row. This is something with excel - it sometimes
      considers empty cells to be included in the sheet." unless parsed.length == VALID_EMPLOYEE_CSV_LINE_SIZE
    else
      puts "Warning: Line size: #{parsed.length} is incorrect for line number: #{csv_line_number},
      should be #{VALID_EMPLOYEE_CSV_LINE_SIZE_LEAN} - will proceed anyway.\n*This warning can heppen also
      when there are empty cells at the end of each row. This is something with excel - it sometimes
      considers empty cells to be included in the sheet." unless parsed.length == VALID_EMPLOYEE_CSV_LINE_SIZE_LEAN
    end


    employee_context = EmployeeLineProcessingContext.new(csv_line, csv_line_number, company_id)

    begin

      if !lean
        email = parsed[4]
        return nil if (email.nil?)

        external_id = format_string(parsed[0])
        first_name = safe_titleize(parsed[1]).strip
        middle_name = safe_titleize(parsed[2]) if !parsed[2].nil?
        last_name = safe_titleize(parsed[3]).strip
        email = format_string(email.downcase)
        role = format_string(parsed[6])
        rank = parsed[7],
        job_title = format_string(parsed[8])
        birth_date = parse_date_for_xls(parsed[9])
        gender = format_string(parsed[10]).try(:downcase)
        marital_status = format_string(parsed[11])
        work_start_date = parse_date_for_xls(parsed[12])
        qual = format_string(parsed[13])
        home_address = format_string(parsed[14])
        #office_address = format_string(parsed[15])
        pos = format_string(parsed[16])
        group_name = safe_titleize(parsed[17])
        id_number = format_string(parsed[18])
        phone_number = format_string(parsed[19])
        del = is_delete?(parsed)
        merge = merge_with(parsed)
        
      else

        gender = format_string(parsed[7]).try(:downcase)

        email = parsed[3]
        email = format_string(email.downcase) if (!email.nil?)
        external_id = format_string(parsed[0])
        first_name = safe_titleize(parsed[1])
        last_name = safe_titleize(parsed[2])
        role = format_string(parsed[4])
        rank = parsed[5]
        job_title = format_string(parsed[6])
        gender = gender
        office_address = format_string(parsed[8])
        group_name = safe_titleize(parsed[9]).strip if !parsed[9].nil?
        phone_number = format_string(parsed[10])
        factor_a = format_string(parsed[11])
        factor_b = format_string(parsed[12])
        factor_c = format_string(parsed[13])
        factor_d = format_string(parsed[14])
        factor_e = format_string(parsed[15])
        factor_f = format_string(parsed[16])
        factor_g = format_string(parsed[17])
        factor_h = format_string(parsed[18])
        factor_i = format_string(parsed[19])
        factor_j = format_string(parsed[20])
        
        unless (parsed[21].nil?)
          existing_id=format_string(parsed[21])
        else
          existing_id=nil
        end
        del = is_delete?(parsed)
        merge = merge_with(parsed)
        #del = (parsed[22]=='D')
      end
      Rails.logger.info([email,del].join(','))
      employee_context.attrs.merge!(
        company_id:       company_id,
        external_id:      external_id,
        first_name:       first_name,
        middle_name:      middle_name,
        last_name:        last_name,
        email:            email,
        role:             role,
        rank:             Rank.find_by_name(rank),
        job_title:        job_title,
        date_of_birth:    birth_date,
        gender:           gender,
        marital_status:   marital_status,
        work_start_date:  work_start_date,
        qualifications:   qual,
        home_address:     home_address,
        office_address:   office_address,
        position_scope:   pos,
        group_name:       group_name,
        id_number:        id_number,
        phone_number:     phone_number,
        snapshot_id:      sid,
        delete:           del,
        merge:           merge,
        factor_a:         factor_a,
        factor_b:         factor_b,
        factor_c:         factor_c,
        factor_d:         factor_d,
        factor_e:         factor_e,
        factor_f:         factor_f,
        factor_g:         factor_g,
        factor_h:         factor_h,
        factor_i:         factor_i,
        factor_j:         factor_j,
        
      )
      unless (parsed[21].nil?)
        employee_context.attrs.merge!(existing_id: existing_id)
      end
    rescue => e
      puts "Exception loading employee with email: #{email} with error: #{e.message}"
      puts e.backtrace[0..20]
      puts "\n\n"
      raise e.message
    end
    return [employee_context]
  end

  def process_xls_groups(parsed, company_id, csv_line, csv_line_number, sid, lean)
    date = parsed[4] || Time.now
    date = date.strftime('%Y-%m-%d')
    name = lean ? safe_titleize(parsed[0]) : safe_titleize(parsed[1])
    english_name = lean ? nil : format_string(parsed[5])
    group_context = GroupLineProcessingContext.new(csv_line, csv_line_number, company_id)
    group_context.attrs.merge!(
      company_id: company_id,
      external_id: parsed[0].nil? ? name : parsed[0], ## If external_id is not provided then default to the name
      name: name,
      parent_external_id: (lean ? parsed[1] : parsed[2]),
      delete: parsed[3].nil? ? false : !parsed[3].empty?,
      date: date,
      english_name: english_name,
      snapshot_id: sid
    )
    return [group_context]
  end


  def format_string(s)
    return nil if (s.nil? || s == '')
    s = s.to_s
    s = s.strip
    return s.strip
  end
  #################################################################################

  private

  include LineProcessingContextClasses

  def check_correct_names(csv_headline, csv_type)
    expected_headings = csv_headings(csv_type) #array of headings
    actual_headings = csv_headline.split(',')
    str = ''
    for i in 0..expected_headings.length
      next if expected_headings[i].nil?
      if expected_headings[i].strip != actual_headings[i].strip
        str += "Field #{i} is >>>#{actual_headings[i].strip}<<< instead of >>>#{expected_headings[i].strip}<<<.\n "
      end
    end
    return str
  end

  def csv_headings(csv_type)
    case csv_type
    when EMPLOYEES_CSV #1
      return ['external_id', 'first_name', 'middle_name', 'last_name', 'email',
              'alias_emails', 'role', 'rank', 'job_title', 'date_of_birth',
              'gender', 'marital_status', 'work_start_date', 'qualifications', 'home_address',
              'office_address', 'position_scope', 'group_name', 'id_number', 'delete'
              ]
    when MANAGMENT_RELATION_CSV #3
      return ["manager_external_id", "employee_external_id", "relation_type", "delete"]
    when NETWORK  #ASAF BYEBUG just add here?
      return ["from_employee_id", "to_employee_id", "value", "snapshot"]
    when GROUPS_CSV
      return ['exteral_id','group_name','parent_group_external_id','delete','group_update_date']
    end
  end

  def check_line_size(csv_headline, csv_type)
    expected_size = expected_line_size(csv_type)
    actual_size   = csv_headline.split(",").size
    return '' if actual_size == expected_size
    return "Number of columns is incorrect. Expected: #{expected_size}, actual: #{actual_size}\nHeadings found: #{csv_headline.split(",")}"
  end

  def expected_line_size(csv_type)
    case csv_type
      when EMPLOYEES_CSV
        return VALID_EMPLOYEE_CSV_LINE_SIZE
      when GROUPS_CSV
        return VALID_GROUP_CSV_LINE_SIZE
      when MANAGMENT_RELATION_CSV
        return VALID_MANAGMENT_RELATION_CSV_LINE_SIZE
      when NETWORK
        return VALID_NETWORK_CSV_LINE_SIZE
    end
  end

  def is_delete?(parsed)
    parsed[22]=='D'
 end
  def merge_with(parsed)
    return "" if (parsed.nil? || parsed[22].nil? || parsed[22]!='M')
    return parsed[23]
  end

end
