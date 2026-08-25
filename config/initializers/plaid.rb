require Rails.root.join("lib/maybe_boot/plaid_environment")

Rails.application.configure do
  PlaidEnvironment.apply!(config, require_app_domain: Rails.env.production?)
end
