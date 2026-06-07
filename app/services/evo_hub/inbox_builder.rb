module EvoHub
  class InboxBuilder
    SUPPORTED_TYPES = {
      'whatsapp_cloud' => :build_whatsapp,
      'facebook_page' => :build_facebook,
      'facebook' => :build_facebook,
      'instagram' => :build_instagram
    }.freeze
    WEBHOOK_EVENTS = %w[channel_connected channel_disconnected event_received webhook_delivered webhook_failed].freeze

    class UnsupportedChannelType < StandardError; end

    def initialize(channel_type:, name:, channel_credentials_id: nil)
      @channel_type = channel_type.to_s
      @name = name.to_s.presence || "#{@channel_type.humanize} via Evo Hub"
      @channel_credentials_id = channel_credentials_id.presence
    end

    def perform
      handler = SUPPORTED_TYPES[@channel_type]
      raise UnsupportedChannelType, "channel_type=#{@channel_type} cannot use Evo Hub" unless handler

      ActiveRecord::Base.transaction do
        channel = send(handler)
        hub_response = create_in_hub(channel)
        persist_hub_metadata(channel, hub_response)
        inbox = Inbox.create!(channel: channel, name: @name)
        { inbox: inbox, public_link: extract_public_link(hub_response) }
      end
    end

    private

    def client
      @client ||= EvoHub::Client.new
    end

    def webhook_url
      base = ENV.fetch('BACKEND_URL', 'http://localhost:3000')
      "#{base.chomp('/')}/webhooks/evolution_hub"
    end

    def webhook_secret
      GlobalConfigService.load('EVOLUTION_HUB_WEBHOOK_SECRET', nil)
    end

    def build_whatsapp
      Channel::Whatsapp.create!(
        phone_number: "+0000#{SecureRandom.random_number(10**10)}",
        provider: 'whatsapp_cloud',
        provider_config: {
          'api_key' => '',
          'phone_number_id' => '',
          'business_account_id' => '',
          'evolution_hub' => { 'status' => 'pending' }
        }
      )
    end

    def build_facebook
      Channel::FacebookPage.create!(
        user_access_token: '',
        page_access_token: '',
        page_id: "pending_#{SecureRandom.hex(6)}",
        evolution_hub_meta: { 'status' => 'pending' }
      )
    end

    def build_instagram
      Channel::Instagram.create!(
        access_token: '',
        instagram_id: "pending_#{SecureRandom.hex(6)}",
        expires_at: 60.days.from_now,
        evolution_hub_meta: { 'status' => 'pending' }
      )
    end

    def hub_channel_type(channel)
      case channel
      when Channel::Whatsapp then 'whatsapp'
      when Channel::FacebookPage then 'facebook'
      when Channel::Instagram then 'instagram'
      end
    end

    def create_in_hub(channel)
      hub_response = client.create_channel(
        type: hub_channel_type(channel),
        name: @name,
        external_id: channel.id.to_s,
        webhook_url: webhook_url,
        webhook_secret: webhook_secret,
        webhook_events: WEBHOOK_EVENTS,
        channel_credentials_id: @channel_credentials_id
      )
      validate_channel_response!(hub_response)
      ensure_webhook!(hub_response)
      hub_response
    end

    def persist_hub_metadata(channel, hub_response)
      channel_body = extract_channel_body(hub_response)
      hub_block = {
        'channel_id' => channel_body['id'],
        'channel_token' => channel_body['token'],
        'channel_credentials_id' => channel_body['channel_credentials_id'],
        'webhook_id' => hub_response.is_a?(Hash) ? hub_response['webhook_id'] : nil,
        'public_link' => EvoHub::Client.public_link(channel_body['token']),
        'status' => 'pending'
      }

      if channel.is_a?(Channel::Whatsapp)
        provider_config = (channel.provider_config || {}).deep_dup
        provider_config['evolution_hub'] = hub_block
        channel.update!(provider_config: provider_config)
      else
        channel.update!(evolution_hub_meta: (channel.evolution_hub_meta || {}).merge(hub_block))
      end
    end

    def extract_public_link(hub_response)
      channel_body = extract_channel_body(hub_response)
      EvoHub::Client.public_link(channel_body['token'])
    end

    def ensure_webhook!(hub_response)
      return if hub_response['webhook_id'].present?

      channel_body = extract_channel_body(hub_response)
      webhook = client.create_webhook(
        name: "EvoCRM - #{@name}",
        url: webhook_url,
        events: WEBHOOK_EVENTS,
        secret: webhook_secret,
        channels: [channel_body['id']]
      )
      hub_response['webhook_id'] = extract_webhook_id(webhook)
      return if hub_response['webhook_id'].present?

      raise EvoHub::Client::RequestError.new(
        'Evolution Hub created the channel but did not return a webhook id',
        body: webhook
      )
    end

    def validate_channel_response!(hub_response)
      channel_body = extract_channel_body(hub_response)
      return if channel_body['id'].present? && channel_body['token'].present?

      raise EvoHub::Client::RequestError.new(
        'Evolution Hub did not return a valid channel payload',
        body: hub_response
      )
    end

    def extract_channel_body(hub_response)
      return {} unless hub_response.is_a?(Hash)

      hub_response['channel'].is_a?(Hash) ? hub_response['channel'] : hub_response
    end

    def extract_webhook_id(webhook_response)
      return nil unless webhook_response.is_a?(Hash)

      webhook_response['id'] || webhook_response.dig('webhook', 'id')
    end
  end
end
