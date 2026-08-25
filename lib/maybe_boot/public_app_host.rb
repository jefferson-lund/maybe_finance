class PublicAppHost
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1].freeze

  def self.parse(domain)
    raw = domain.to_s.strip
    return nil if raw.empty?
    return nil if raw.match?(%r{[/?#@]})
    return nil if raw.include?("://")

    uri = URI.parse("https://#{raw}")
    explicit_port = raw.match(/:(\d+)\z/)&.captures&.first&.to_i
    return nil if explicit_port && !explicit_port.between?(1, 65_535)
    return nil if uri.userinfo.present?
    return nil if uri.host.blank?
    return nil if uri.host.include?(":") # IPv6 literals need explicit support later

    host = uri.host.downcase
    return nil unless host.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*\z/)

    if explicit_port
      "#{host}:#{explicit_port}"
    else
      host
    end
  rescue URI::InvalidURIError
    nil
  end

  def self.parse!(domain)
    parse(domain) || raise(ArgumentError, "Invalid APP_DOMAIN=#{domain.inspect}. Use a hostname, optionally with a port.")
  end

  def self.local?(domain)
    host = parse(domain)
    host.present? && LOOPBACK_HOSTS.include?(host.split(":", 2).first)
  end

  def self.hostname(domain)
    parse(domain)&.split(":", 2)&.first
  end

  def self.allowed_hosts(domain)
    host = hostname(domain)
    return [] unless host

    [ host ]
  end

  def self.configure_host_authorization!(config, domain)
    return unless config.app_mode.self_hosted?

    parse!(domain)
    config.hosts = allowed_hosts(domain)
    config.host_authorization = { exclude: method(:health_check_request?) }
  end

  def self.health_check_request?(request)
    request.path == "/up"
  end

  def self.configure_action_cable!(config, domain)
    return unless config.app_mode.self_hosted?

    config.action_cable.allowed_request_origins = action_cable_origins(domain)
    config.action_cable.allow_same_origin_as_host = false
  end

  def self.url_options(domain)
    host = parse(domain)
    return {} unless host

    hostname, port = host.split(":", 2)
    protocol = local?(host) ? "http" : "https"
    port = port&.to_i
    port = nil if (protocol == "http" && port == 80) || (protocol == "https" && port == 443)

    {
      host: hostname,
      protocol: protocol,
      port: port
    }
  end

  def self.action_cable_origins(domain)
    options = url_options(domain)
    return [] if options.empty?

    port = ":#{options[:port]}" if options[:port]
    [ "#{options[:protocol]}://#{options[:host]}#{port}" ]
  end
end
