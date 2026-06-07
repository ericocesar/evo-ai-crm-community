require 'httparty'

module EvoHub
  class Client
    include HTTParty
    default_timeout 10

    HUB_API_URL = 'https://api.evohub.ai'
    HUB_FRONTEND_URL = 'https://app.evohub.evolutionfoundation.com.br'

    class ConfigurationError < StandardError; end
    class RequestError < StandardError
      attr_reader :status, :body, :code, :variables

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
        @code, @variables = parse_structured_error(body)
      end

      private

      def parse_structured_error(body)
        parsed = body.is_a?(Hash) ? body : (JSON.parse(body) rescue nil)
        err = parsed.is_a?(Hash) ? parsed['error'] : nil
        return [err['code'], err['variables']] if err.is_a?(Hash)

        [nil, nil]
      end
    end

    def create_channel(type:, name:, external_id:, webhook_url:, webhook_secret:, webhook_events:, channel_credentials_id: nil)
      post_json('/api/v1/channels', {
        name: name,
        type: type,
        external_id: external_id,
        webhook_url: webhook_url,
        webhook_secret: webhook_secret,
        webhook_events: webhook_events,
        channel_credentials_id: channel_credentials_id
      }.compact)
    end

    def get_channel(channel_id)
      get_json("/api/v1/channels/#{channel_id}")
    end

    def create_webhook(name:, url:, events:, secret:, channels:)
      post_json('/api/v1/webhooks', {
        name: name,
        url: url,
        events: events,
        secret: secret,
        all_channels: false,
        channels: channels
      })
    end

    def self.public_link(channel_token)
      return nil if channel_token.blank?

      "#{HUB_FRONTEND_URL}/connect/#{channel_token}"
    end

    private

    def api_key
      key = GlobalConfigService.load('EVOLUTION_HUB_API_KEY', nil)
      raise ConfigurationError, 'EVOLUTION_HUB_API_KEY not configured' if key.blank?

      key
    end

    def headers
      {
        'Authorization' => "Bearer #{api_key}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    end

    def get_json(path)
      response = HTTParty.get("#{HUB_API_URL}#{path}", headers: headers, timeout: 10)
      handle(response, "GET #{path}")
    end

    def post_json(path, body)
      response = HTTParty.post("#{HUB_API_URL}#{path}", body: body.to_json, headers: headers, timeout: 10)
      handle(response, "POST #{path}")
    end

    def handle(response, operation)
      return response.parsed_response if response.code.between?(200, 299)

      raise RequestError.new(
        "Evolution Hub #{operation} failed with HTTP #{response.code}",
        status: response.code,
        body: response.body
      )
    end
  end
end
