require Rails.root.join("lib/maybe_boot/plaid_environment")

Rails.application.configure do
  PlaidEnvironment.apply!(config)
end
