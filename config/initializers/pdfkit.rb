PDFKit.configure do |config|
  config.wkhtmltopdf = '/usr/bin/wkhtmltopdf'
  config.default_options = {
  :enable_local_file_access => true,
  'page-size': 'A4',
  'margin-top': '0in',
  'margin-right': '0in',
  'margin-bottom': '0in',
  'margin-left': '0in',
  'encoding': "UTF-8",
  'dpi': 150,
  }

end