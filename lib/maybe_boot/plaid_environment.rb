class PlaidEnvironment
  NAMES = %w[sandbox production].freeze

  def self.apply!(config, require_app_domain: false)
    environment = normalize(ENV["PLAID_ENV"])

    config.plaid = nil
    config.plaid_eu = nil

    config.plaid = build_configuration!(
      client_id: ENV["PLAID_CLIENT_ID"],
      secret: ENV["PLAID_SECRET"],
      pair_name: "PLAID_CLIENT_ID and PLAID_SECRET"
    )

    config.plaid_eu = build_configuration!(
      client_id: ENV["PLAID_EU_CLIENT_ID"],
      secret: ENV["PLAID_EU_SECRET"],
      pair_name: "PLAID_EU_CLIENT_ID and PLAID_EU_SECRET"
    )

    if require_app_domain && (config.plaid || config.plaid_eu)
      domain = PublicAppHost.parse!(ENV["APP_DOMAIN"])
      if environment == "production" && PublicAppHost.local?(domain)
        raise ArgumentError, "PLAID_ENV=production requires a public APP_DOMAIN served over HTTPS"
      end
    end
  end

  def self.normalize(name)
    raw = name.to_s.strip.downcase

    if raw == "development"
      raise ArgumentError, "PLAID_ENV=development is no longer valid. Plaid retired that environment. Set PLAID_ENV=sandbox to link Plaid's test banks, or PLAID_ENV=production to link real banks."
    end

    raw = "sandbox" if raw.blank?

    unless NAMES.include?(raw)
      raise ArgumentError, "Invalid PLAID_ENV=#{name.inspect}. Use sandbox or production."
    end

    raw
  end

  def self.server_index(name)
    Plaid::Configuration::Environment.fetch(normalize(name))
  end

  def self.build_configuration!(client_id:, secret:, pair_name:)
    id_present = client_id.to_s.strip.present?
    secret_present = secret.to_s.strip.present?

    if id_present ^ secret_present
      raise ArgumentError, "#{pair_name} must both be set, or both be omitted"
    end

    return nil unless id_present

    configuration = Plaid::Configuration.new
    configuration.server_index = server_index(ENV["PLAID_ENV"])
    configuration.api_key["PLAID-CLIENT-ID"] = client_id.to_s.strip
    configuration.api_key["PLAID-SECRET"] = secret.to_s.strip
    configuration
  end
  private_class_method :build_configuration!
end
