class PersonalReportMailer < ActionMailer::Base
  default from: 'donotreply@mail.step-ahead.com'

  def personal_report_email(email, attachment_path, subject, body)
    @subject = subject
    @body = body

    attachments['personal_report.pdf'] = File.read(attachment_path)
    mail(subject: subject, to: email)
  end
end
