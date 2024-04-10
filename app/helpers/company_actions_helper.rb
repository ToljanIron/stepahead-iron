module CompanyActionsHelper
    TIMEOUT = 60 * 60 * 24 * 7

    def self.upload_company_logo(logo, company)
        begin
            img_suffix = logo.original_filename[-3..-1]

            if (img_suffix != 'jpg' && img_suffix != 'png')
                return "Logo suffix should be one of: .jpg or .png"
            end

            logo_url = upload_image(logo, company.id)
        
            company.update!(
                logo_url: logo_url,
                logo_url_last_updated: Time.now
            )

            EventLog.create!(
                message: "Logo uploaded for: #{company.name}",
                event_type_id: 14
            )
        rescue => e
            errmsg = "ERROR uploading logo: #{e.message}"
        
            EventLog.create!(
                message: "ERROR company: #{company.name}, msg: #{errmsg}",
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
        obj = bucket.object("companies/#{cid}/#{img.original_filename}")
    
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
        return "companies/#{cid}/#{base_name}.#{image_type}"
    end
end