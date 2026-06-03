# Register middleware to intercept Facebook webhook requests and log/process feed events
# This middleware runs before the facebook-messenger gem processes messaging events
# Require the middleware class explicitly before registering
require_relative '../../app/middleware/facebook_webhook_logger'

if Rails.application.config.middleware.any? { |m| m.klass.to_s == 'ActionDispatch::Static' }
  Rails.application.config.middleware.insert_before ActionDispatch::Static, FacebookWebhookLogger
else
  Rails.application.config.middleware.use FacebookWebhookLogger
end

