# Register middleware to intercept Facebook webhook requests and log/process feed events
# This middleware runs before the facebook-messenger gem processes messaging events
# Require the middleware class explicitly before registering
require_relative '../../app/middleware/facebook_webhook_logger'

if Rails.application.config.public_file_server.enabled
  Rails.application.config.middleware.insert_before ActionDispatch::Static, FacebookWebhookLogger
else
  Rails.application.config.middleware.use FacebookWebhookLogger
end

