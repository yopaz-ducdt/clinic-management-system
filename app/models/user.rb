class User < ApplicationRecord
  devise :database_authenticatable,
         :recoverable,
         :rememberable,
         :omniauthable,
         omniauth_providers: [ :google_oauth2 ]

  has_many :patients, foreign_key: "managed_by_user_id"
  has_one :doctor

  ROLE = %w[admin doctor patient].freeze
  STATUS = %w[active inactive pending_profile].freeze

  validates :phone, :national_id, presence: true, if: -> {
    status.in?(%w[active inactive])
  }

  validates :password, presence: true, length: { minimum: 6, maximum: 64 }, if: -> {
    provider.blank? && encrypted_password.blank?
  }

  validates :role, presence: true, inclusion: { in: ROLE }
  validates :status, presence: true, inclusion: { in: STATUS }

  validates :email, presence: true, if: -> { status == "pending_profile" }
  validates :email, uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP },
            allow_nil: true

  validates :national_id, uniqueness: true, allow_nil: true

  validates :password, confirmation: true, if: -> { password.present? }

  def self.find_for_database_authentication(warden_conditions)
    conditions = warden_conditions.to_h
    login = conditions.delete(:login).to_s.strip.downcase
    where(conditions).where(
      "lower(email) = :v OR phone = :v OR national_id = :v", v: login
    ).first
  end

  def self.from_omniauth(auth)
    user = User.find_by(email: auth.info.email)

    if user
      user.update(provider: auth.provider, uid: auth.uid) if user.provider.blank?
      user
    else
      create!(
        email: auth.info.email,
        provider: auth.provider,
        uid: auth.uid,
        role: "patient",
        status: "pending_profile"
      )
    end
  end
end
