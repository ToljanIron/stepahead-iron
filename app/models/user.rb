class User < ActiveRecord::Base
  ROLE_ADMIN   = 'admin'
  ROLE_HR      = 'hr'
  ROLE_EMP     = 'emp'
  ROLE_MANAGER = 'manager'

  LOGIN_ATTEMPTS_TOLERANCE = 30

  attr_accessor :undigest_token

  has_many :questionnaire_permissions
  belongs_to :company

  before_save { self.email = email.downcase }
  before_create :create_remember_token

  VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
  validates :email, presence:   true,
  format:     { with: VALID_EMAIL_REGEX },
  uniqueness: { case_sensitive: false }
  has_secure_password
  validates :first_name, length: { maximum: 50 }
  validates :last_name, length: { maximum: 40 }

  enum role: [:super_admin, :admin, :emp, :manager, :editor]  #enum role: [:admin, :hr, :emp, :manager]
  # enum level: [:super_admin, :adminn, :editor]

  validates :permissible_group, presence: true, if: :is_manager?

  validates :document_encryption_password, length: { minimum: 7 }, :allow_blank => true

  def is_manager?
    return role == ROLE_MANAGER
  end

  scope :not_expired, -> { where('tmp_password_expiry > ?', DateTime.now) }

  def self.new_remember_token
    SecureRandom.urlsafe_base64
  end

  def self.digest(string)
    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST :
    BCrypt::Engine.cost
    BCrypt::Password.create(string, cost: cost)
  end

  def self.new_token
    SecureRandom.urlsafe_base64
  end

  def remember
    self.undigest_token = User.new_token
    update_attribute(:remember_token, User.digest(undigest_token))
  end

  def authenticated?(token)
    begin
      BCrypt::Password.new(remember_token).is_password?(token)
    rescue => e
      error = e.message
      puts "Got exception : #{error}. User was not authenticated."
      false
    end
  end

  def forget
    update_attribute(:remember_token, nil)
  end

  def generate_password_reset_token
    begin
      update_attribute(:password_reset_token, SecureRandom.urlsafe_base64(48))
      update_attribute(:password_reset_token_expiry, DateTime.now + 1.week)
    rescue => e
      error = e.message
      puts "Got exception: #{error}. Rolling back."
      puts e.backtrace
    end
  end

  def send_reset_password_mail(base_url)
    mail = nil
    begin
      mail = UserMailer.reset_password_email(email, password_reset_token, base_url).deliver_now! unless Rails.env.test?
      mail = {} if Rails.env.test?
    rescue => e
      error = e.message
      puts "Got exception: #{error}. Rolling back."
      puts e.backtrace
    end
    return mail
  end

  def authenticate_by_tmp_password?(temporary_password)
    BCrypt::Password.new(tmp_password).is_password?(temporary_password) if tmp_password
  end

  def self.verify_password_token(token)
    @current_user = User.find_by(password_reset_token: token)
    if @current_user && @current_user.password_reset_token_expiry > DateTime.now
      return true
    else
      return false
    end
  end

  ################## N login attempts API ###########################
  def can_login?(max_attempts, lock_delay)
    ret = false

    if is_locked_due_to_max_attempts

      if Time.now.to_i - time_of_last_login_attempt.to_i > lock_delay
        self[:time_of_last_login_attempt] = Time.now
        self[:is_locked_due_to_max_attempts] = false
        ret = true
      else
        ret = false
      end

    else

      self[:number_of_recent_login_attempts] += 1
      if number_of_recent_login_attempts > max_attempts
        self[:number_of_recent_login_attempts] = 0
        if Time.now.to_i - time_of_last_login_attempt.to_i > LOGIN_ATTEMPTS_TOLERANCE
          ret = true
        else
          self[:is_locked_due_to_max_attempts] = true
          ret = false
        end
      else
        ret = true
      end
      self[:time_of_last_login_attempt] = Time.now
    end

    self.save!
    return ret
  end

  ################## Filter groups according to permissions #####################
  def get_permissible_groups_hash(sid)
    cache_key = "filter_authorized_groups-uid-#{id}-sid-#{sid}"
    permissible_groups_hash = CdsUtilHelper.dev_cache_read(cache_key)

    if permissible_groups_hash.nil?
      permissible_groups_arr =
        Group
          .where(external_id: permissible_group)
          .where(snapshot_id: sid)
          .last
          .extract_descendants_ids_and_self

      permissible_groups_hash = {}
      permissible_groups_arr.each do |gid|
        permissible_groups_hash[gid] = true
      end
      CdsUtilHelper.dev_cache_write(cache_key, permissible_groups_hash, 1.minute)
    end
    return permissible_groups_hash
  end

  def authorized_groups(sid)
    permissible_groups_hash = get_permissible_groups_hash(sid)
    return permissible_groups_hash.keys
  end

  def filter_authorized_groups(gids_arr)
    return gids_arr if (role == 'admin' || role == 'super_admin' || role == 'editor')
    return nil if (role != 'manager')

    sid = Group.find(gids_arr.first).snapshot_id
    permissible_groups_hash = get_permissible_groups_hash(sid)
    ret = gids_arr.select { |gid| permissible_groups_hash[gid.to_i] }
    return ret
  end

  def group_authorized?(gid)
    return true  if (role == 'admin' || role == 'super_admin'|| role == 'editor')
    return false if (role != 'manager')
    group = Group.find(gid)
    sid = group.snapshot_id
    top_permissable_group = Group.where(external_id: permissible_group)
                                 .where(snapshot_id: sid)
                                 .last
    return group.nsleft  >= top_permissable_group.nsleft &&
           group.nsright <= top_permissable_group.nsright
  end

  private

  def create_remember_token
    self.remember_token = User.digest(User.new_remember_token)
  end

  public

  def update_user_info(first_name, last_name, doc_encryption_pass)
    update_attribute(:first_name, first_name)
    update_attribute(:last_name, last_name)
    update_attribute(:document_encryption_password, doc_encryption_pass)
    return
  end

  def update_password(old_password, new_password)
    if(BCrypt::Password.new(password_digest).is_password?(old_password))
      update!(email: email, password: new_password)
      return true
    end
    return false
  end
end
