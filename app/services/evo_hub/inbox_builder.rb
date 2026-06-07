module EvoHub
  class InboxBuilder
    SUPPORTED_TYPES = {
      'whatsapp_cloud' => :build_whatsapp,
      'facebook_page' => :build_facebook,
      'facebook' => :build_facebook,
      'instagram' => :build_instagram
    }.freeze

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
      client.create_channel(
        type: hub_channel_type(channel),
        name: @name,
        external_id: channel.id.to_s,
        webhook_url: webhook_url,
        webhook_secret: webhook_secret,
        webhook_events: %w[channel_connected channel_disconnected event_received webhook_delivered webhook_failed],
        channel_credentials_id: @channel_credentials_id
      )
    end

    def persist_hub_metadata(channel, hub_response)
      channel_body = hub_response.is_a?(Hash) ? (hub_response['channel'] || {}) : {}
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
      channel_body = hub_response.is_a?(Hash) ? (hub_response['channel'] || {}) : {}
      EvoHub::Client.public_link(channel_body['token'])
    end
  end
end
