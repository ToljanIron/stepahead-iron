require 'net/http'
require 'uri'

module InteractBackofficeActionsHelper
  include InteractBackofficeHelper

  TIMEOUT = 60 * 60 * 24 * 7

  SMS_TEXT = 'Welcome to StepAhead\'s questionnaire. Please click the link at the bottom the start.'

  EMAIL_SUBJECT = "Welcome to StepAheads survey "
  EMAIL_TEXT = "
    <h1>Hi FIRST_NAME!</h1>
    <p>
    Welcome to StepAhead's survey.
    </p>
    <p>
    We kindly ask you to take a few moments to fill out the survey in <a href=\"LINK\">this link</a>.
    </p>
    <p>
    Your completeion of the quesitonnaire is very important for us and will contribute to the orgainzation's overall success.
    </p>
    <p>
    Thanks for your cooperation.
    </>
  "
  EMAIL_FROM = 'donotreply@mail.2stepahead.com'

  ############################################################
  ## Create a new questionnaire
  ##   - create questionaire
  ##   - create networks
  ##   - copy questions
  ##   - create participants
  ##   - create test participant
  ############################################################
  def self.create_new_questionnaire(cid, qid=nil, rerun=false)
    questcopy = !qid.nil?
    oq = questcopy ? Questionnaire.find(qid) : nil

    ## Attached a snapshot to the questionnaire
    snapshot = Snapshot.create_snapshot_for_questionnaire(cid, Time.now.to_s, qid)
    sid = snapshot.id

    ## Create questionnaire
    name = questcopy ? "#{oq.name} copy-#{sid}" : "Q-#{cid}-#{sid}-#{Time.now.strftime('%Y%m%d-%M')}"
    language_id = questcopy ? oq.language_id : 2
    sms_text = questcopy ? oq.sms_text : SMS_TEXT
    email_text = questcopy ? oq.email_from : EMAIL_TEXT
    email_from = questcopy ? oq.email_from : EMAIL_FROM
    email_subject = questcopy ? oq.email_subject : EMAIL_SUBJECT
    test_user_name = questcopy ? oq.test_user_name : 'Test user'
    test_user_email = questcopy ? oq.test_user_email : 'test@unknown'
    test_user_phone = questcopy ? oq.test_user_phone : '012-3456789'
    prev_questionnaire_id = rerun ? oq.id : nil
    state = questcopy ? :questions_ready : :created

    quest = Questionnaire.create!(
      company_id: cid,
      state: state,
      name: name,
      language_id: language_id,
      sms_text: sms_text,
      email_text: email_text,
      email_from: email_from,
      email_subject: email_subject,
      test_user_name: test_user_name,
      test_user_email: test_user_email,
      test_user_phone: test_user_phone,
      snapshot_id: sid,
      prev_questionnaire_id: prev_questionnaire_id
    )

    ## When copying a questionnaire need to set questionnaire_id field on
    ## the groups in the new snapshot to the new id

    if questcopy
      Group
        .where(snapshot_id: sid)
        .update_all(questionnaire_id: quest.id)

      # Group
      #   .where(questionnaire_id: qid)
      #   .where(snapshot_id: sid)
      #   .update_all(questionnaire_id: quest.id)
    end

    ## Copy over template questions
    questions = []
    if questcopy
      questions = QuestionnaireQuestion.where(questionnaire_id: qid)
    else
      questions = Question.order(:order)
    end

    ii = 0
    new_qid = quest.id
    questions.each do |q|
      ii += 1

      network = NetworkName.find_or_create_by!(
        name: q.title,
        company_id: cid,
        questionnaire_id: new_qid
      )

      QuestionnaireQuestion.create!(
        company_id: cid,
        questionnaire_id: quest.id,
        question_id: q.id,
        network_id: network.id,
        title: q.title,
        body: q.body,
        order: ii,
        min: 1,
        max: 15,
        active: questcopy ? q.active : false,
        is_funnel_question: q.is_funnel_question
      )
    end

    ## Create test participant
    qp = QuestionnaireParticipant.create!(
      employee_id: -1,
      questionnaire_id: quest.id,
      active: true,
      participant_type: 1
    )
    qp.create_token

    ## Copy participants if in copy mode
    if questcopy
      eids = []
      pars = QuestionnaireParticipant
               .where(questionnaire_id: qid)
               .where.not(employee_id: -1)
      pars.each do |p|
        eid = Employee.id_in_snapshot(p.employee_id, sid)
        eids << eid
        qp = QuestionnaireParticipant.create!(
          employee_id: eid,
          questionnaire_id: quest.id,
          active: true
        )
        qp.create_token
      end
      if pars.length > 0
        quest.update_attribute(:state, :notstarted)
      end
    end

    return quest #nil
  end


  ################## Send questionnaire ###############################
  def self.send_test_questionnaire(aq)
    qp = QuestionnaireParticipant.where(
      questionnaire_id: aq.id,
      participant_type: 1
    ).last
    qp.reset_questionnaire
    send_test_sms(aq, qp) if aq.delivery_method == 'sms'
    send_test_email(aq, qp) if aq.delivery_method == 'email'
    raise 'Unrecoginzed delivery method' if(aq.delivery_method == 'sms' && aq.delivery_method == 'email')
  end

  def self.send_test_email(aq, qp)
    emails = aq.test_user_email.split(";").map {|p| p.strip}
    emails.each do |email|
      send_email(
        aq,
        qp,
        email,
        aq.test_user_name
      )
    end
  end

  def self.send_test_sms(aq, qp)
    phones = aq.test_user_phone.split(";").map {|p| p.strip}
    phones.each do |phone|
      send_sms(aq, qp, phone)
    end
  end

  def self.send_live_questionnaire(aq, qp)
    if !Rails.env.production? && !Rails.env.onpremise?
      puts "Not REALLY sending questionnaire to: #{qp.employee.email} because this is not production"
      return
    end
    send_live_sms(aq, qp) if aq.delivery_method == 'sms'
    send_live_email(aq, qp) if aq.delivery_method == 'email'
    raise 'Unrecoginzed delivery method' if(aq.delivery_method == 'sms' && aq.delivery_method == 'email')
  end

  def self.send_live_sms(aq, qp)
    phone = qp.employee.phone_number
    unless phone
      msg = "Not sending to participant: #{qp.id} because phone is nil" if phone.nil?
      puts msg
      EventLog.create!(message: msg, event_type_id: 11)
      return
    end

    phone = phone.gsub('-','')
    is_valid = phone.split('').select { |b| b.match(/\d/) }.join.length == 10
    unless is_valid
      msg = "ERROR - Invalid phone number: #{phone} for participant: #{qp.id}"
      puts msg
      EventLog.create!(message: msg, event_type_id: 11)
      return
    end

    send_sms(aq, qp, phone)
  end

  def self.send_live_email(aq, qp)
    send_email(
      aq,
      qp,
      qp.employee.email,
      qp.employee.first_name
    )
  end

  def self.send_email(aq, qp, email_address, user_name)
    puts "Sending to: #{email_address}"

    subject = aq.email_subject  if qp.language_id == 1
    subject = aq.email_subject2 if qp.language_id == 2
    subject = aq.email_subject3 if qp.language_id == 3

    email_text = aq.email_text.clone  if qp.language_id == 1
    email_text = aq.email_text2.clone if qp.language_id == 2
    email_text = aq.email_text3.clone if qp.language_id == 3

    em = ExampleMailer.sample_email(
      email_address,
      subject,
      aq.email_from,
      user_name,
      qp.create_link,
      email_text
    )
    em.deliver
  end

  def self.send_sms(aq, qp, phone_number)
    if(phone_number.starts_with?('0') || phone_number.starts_with?('+972'))
      return self.send_sms_019(aq, qp, phone_number)
    else
      return self.send_sms_twilio(aq, qp, phone_number)
    end
  end

  def self.send_sms_twilio(aq, qp, phone_number)
    puts "Sending SMS to questionnaire participant: #{qp.id}"
    Dotenv.load if Rails.env.development? || Rails.env.onpremise?
    from        = ENV['TWILIO_FROM_PHONE']
    account_sid = ENV['TWILIO_ACCOUNT_SID']
    auth_token  = ENV['TWILIO_AUTH_TOKEN']
    client = Twilio::REST::Client.new account_sid, auth_token
    sms_text = aq.sms_text
    body = "#{sms_text} #{qp.create_link}"
    puts ">>>> from: #{from}, sid: #{account_sid}, token: #{auth_token}"
    res=client.messages.create(
      from: from,
      to:   phone_number,
      body: body
    )
    return(['Twilio',res])

  end
  def self.send_sms_019(aq, qp, phone_number)
    puts "Sending SMS to questionnaire participant: #{qp.id}"
    Dotenv.load if Rails.env.test? || Rails.env.onpremise?
    url = URI.parse("https://019sms.co.il/api")
    username = ENV['SMS_019_USERNAME']
    source = 'StepAhead'
    sms_text = aq.sms_text
    body = "#{sms_text} #{qp.create_link}"
  
    xml = <<~XML
      <?xml version='1.0' encoding='UTF8'?>
      <sms>
        <user>
            <username>#{username}</username>
        </user>
        <source>#{source}</source>
        <destinations>
            <phone>+972#{phone_number.gsub('+972','').gsub('-','').to_i.to_s}</phone>
        </destinations>
        <message>#{body}</message>
      </sms>
    XML
  
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true if url.scheme == "https"
    
    request = Net::HTTP::Post.new(url.path, initheader={'Content-Type' => 'application/xml', 'Authorization'=>ENV['SMS_019_TOKEN']})
    request.body = xml
    response = http.request(request)

    puts "Response: #{response.body}"
    
    return(['019',response.body.include?('<status>0</status>')])
  end
  
  




########################################################

  ##########################################
  # Run questinonaire:
  #  - Change questionnaire state
  #  - Send notifications to all participants
  ##########################################
  def self.run_questionnaire(aq)
    res = []
    aq.update!(state: :sent)
    res = send_questionnaires(aq)
    return res
  end

  def self.send_questionnaires(aq)
    res = []
    qps = QuestionnaireParticipant
            .where(questionnaire_id: aq.id)
            .where.not(employee_id: -1)
            .where.not(status: 3)
            .where(active: true)
    ii = 0
    num_messages = qps.count
    qps.each do |qp|
      ii += 1
      puts "Sending email number #{ii} out of #{num_messages}"
      begin
        send_live_questionnaire(aq, qp)
      rescue => ex
        errmsg = "Error while sending to participant: #{qp.employee.id} - #{ex.message}"
        puts errmsg
        puts ex.backtrace
        res << errmsg
      end
    end
  end

  ###########################################
  # Close questionnaire
  ###########################################
  def self.close_questionnaire(aq)
    puts "In close_questionaaire"
    aq.freeze_questionnaire
  end

################## Upload image ########################
  def self.upload_employee_img(img, eid)

    begin
      img_id = img.original_filename[0..-5]
      emp = Employee.find(eid)
      cid = emp.company_id
      res = check_img_name(img_id, emp, img.original_filename[-3..-1] )
      return res unless res.nil?
      img_url = upload_image(img, cid)

      emp.update!(
        img_url: img_url,
        img_url_last_updated: Time.now
      )
      EventLog.create!(
        message: "Image created for: #{emp.email}",
        event_type_id: 14
      )
    rescue => e
      errmsg = "ERROR loading image: #{e.message}"
      puts errmsg
      puts e.backtrace

      EventLog.create!(
        message: "ERROR emp: #{emp.email}, msg: #{errmsg}",
        event_type_id: 14
      )

      return errmsg
    end
    return nil
  end

  def self.upload_image(img, cid)
    s3_access_key        = ENV['s3_access_key']
    s3_secret_access_key = ENV['s3_secret_access_key']
    s3_bucket_name       = ENV['s3_bucket_name']
    s3_region            = ENV['s3_region']

    Aws.config.update({
      region: s3_region,
      credentials: Aws::Credentials.new(s3_access_key, s3_secret_access_key)
    })

    signer = Aws::S3::Presigner.new
    s3 =     Aws::S3::Resource.new
    bucket = s3.bucket(s3_bucket_name)
    obj = bucket.object("employees/cid-#{cid}/#{img.original_filename}")

    ## Resize the file
    if (File.size(img.path) > 60000)
      res = `convert #{img.path} -resize 220x100 -auto-orient #{img.path}`
      puts res
    end

    ## Upload the file
    obj.upload_file(img.path)

    ## Get a safe url back
    img_url = create_s3_object_url(
            img.original_filename[0..-5],
            cid,
            signer,
            bucket,
            s3_bucket_name)

    return img_url
  end

  def self.create_s3_object_url(base_name, cid, signer, bucket, bucket_name)
    url = create_url(base_name, cid, 'jpg')
    puts "url: #{url}"
    url = bucket.object(url).exists? ? url : create_url(base_name, cid, 'png')

    if bucket.object(url).exists?
      safe_url = signer.presigned_url(
                   :get_object,
                   bucket: bucket_name,
                   key: url,
                   expires_in: TIMEOUT)
      return safe_url
    else
      raise "Coulnd not find image for #{base_name}.jpg or #{base_name}.png"
    end
  end

  def self.create_url(base_name, cid, image_type)
    return "employees/cid-#{cid}/#{base_name}.#{image_type}"
  end

  def self.check_img_name(img_id, emp, img_suffix)
    if (img_id != emp.email && img_id != emp.phone_number)
      return "Image name does not match participant email or phone number"
    end
    if (img_suffix != 'jpg' && img_suffix != 'png')
      return "Image suffix should be one of: .jpg or .png"
    end
    return nil
  end
############################################################################
end
