module EvoHub
  class ExistingChannelLinker
    SUPPORTED_TYPES = {
      'whatsapp_cloud' => 'whatsapp',
      'facebook_page' => 'facebook',
      'facebook' => 'facebook',
      'instagram' => 'instagram'
    }.freeze

    class UnsupportedChannelType < StandardError; end
    class ChannelTypeMismatch < StandardError; end
    class AlreadyLinked < StandardError; end

    def initialize(channel_type:, name:, hub_channel_id:)
      @channel_type = channel_type.to_s
      @name = name.to_s.presence || "#{@channel_type.humanize} via Evo Hub"
      @hub_channel_id = hub_channel_id.to_s
    end

    def perform
      raise UnsupportedChannelType, "channel_type=#{@channel_type} cannot use Evo Hub" unless SUPPORTED_TYPES.key?(@channel_type)
      raise ArgumentError, 'hub_channel_id is required' if @hub_channel_id.blank?

      hub_channel = extract_channel(client.get_channel(@hub_channel_id))
      validate_channel_payload!(hub_channel)
      @hub_channel_id = hub_channel['id'].to_s
      validate_type_match!(hub_channel)
      validate_not_already_linked!

      ActiveRecord::Base.transaction do
        webhook = extract_webhook(client.create_webhook(
          name: "EvoCRM - #{@name}",
          url: webhook_url,
          events: %w[channel_connected channel_disconnected event_received webhook_delivered webhook_failed],
          secret: GlobalConfigService.load('EVOLUTION_HUB_WEBHOOK_SECRET', nil),
          channels: [@hub_channel_id]
        ))
        channel = build_channel(hub_channel, webhook)
        inbox = Inbox.create!(channel: channel, name: @name)
        { inbox: inbox, hub_channel: hub_channel }
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

    def validate_type_match!(hub_channel)
      return if hub_channel.is_a?(Hash) && hub_channel['type'] == SUPPORTED_TYPES[@channel_type]

      raise ChannelTypeMismatch, 'Hub channel type does not match requested channel type'
    end

    def validate_channel_payload!(hub_channel)
      return if hub_channel.is_a?(Hash) && hub_channel['id'].present? && hub_channel['token'].present?

      raise EvoHub::Client::RequestError.new(
        'Evolution Hub did not return a valid channel payload',
        body: hub_channel
      )
    end

    def validate_not_already_linked!
      already = Channel::Whatsapp.where("provider_config -> 'evolution_hub' ->> 'channel_id' = ?", @hub_channel_id).exists?
      already ||= Channel::FacebookPage.where("evolution_hub_meta ->> 'channel_id' = ?", @hub_channel_id).exists?
      already ||= Channel::Instagram.where("evolution_hub_meta ->> 'channel_id' = ?", @hub_channel_id).exists?
      raise AlreadyLinked, "Hub channel #{@hub_channel_id} is already linked to another inbox" if already
    end

    def build_channel(hub_channel, webhook)
      hub_block = {
        'channel_id' => hub_channel['id'],
        'channel_token' => hub_channel['token'],
        'channel_credentials_id' => hub_channel['channel_credentials_id'],
        'webhook_id' => webhook['id'],
        'public_link' => EvoHub::Client.public_link(hub_channel['token']),
        'status' => 'active',
        'linked' => true
      }

      case @channel_type
      when 'whatsapp_cloud'
        meta = hub_channel['meta_connection'] || {}
        Channel::Whatsapp.create!(
          phone_number: extract_phone_number(meta),
          provider: 'whatsapp_cloud',
          provider_config: {
            'api_key' => '',
            'phone_number_id' => meta['phone_number_id'].to_s,
            'business_account_id' => meta['waba_id'].to_s,
            'waba_id' => meta['waba_id'].to_s,
            'evolution_hub' => hub_block
          }
        )
      when 'facebook_page', 'facebook'
        fb = hub_channel['facebook_connection'] || {}
        Channel::FacebookPage.create!(
          user_access_token: '',
          page_access_token: '',
          page_id: fb['page_id'].presence || "pending_#{SecureRandom.hex(6)}",
          evolution_hub_meta: hub_block
        )
      when 'instagram'
        ig = hub_channel['instagram_connection'] || {}
        Channel::Instagram.create!(
          access_token: '',
          instagram_id: ig['instagram_user_id'].presence || "pending_#{SecureRandom.hex(6)}",
          expires_at: 60.days.from_now,
          evolution_hub_meta: hub_block
        )
      end
    end

    def extract_channel(response)
      return {} unless response.is_a?(Hash)

      candidates = [
        response['channel'],
        response['data'].is_a?(Hash) ? response['data']['channel'] : nil,
        response['data'],
        response
      ]
      candidates.find { |candidate| candidate.is_a?(Hash) && candidate['id'].present? } || {}
    end

    def extract_webhook(response)
      return {} unless response.is_a?(Hash)

      candidates = [
        response['webhook'],
        response['data'].is_a?(Hash) ? response['data']['webhook'] : nil,
        response['data'],
        response
      ]
      webhook = candidates.find { |candidate| candidate.is_a?(Hash) && candidate['id'].present? } || {}
      return webhook if webhook['id'].present?

      raise EvoHub::Client::RequestError.new(
        'Evolution Hub did not return a valid webhook payload',
        body: response
      )
    end

    def extract_phone_number(meta)
      list = meta['phone_numbers']
      if list.is_a?(Array) && list.first.is_a?(Hash) && list.first['display_phone_number'].present?
        list.first['display_phone_number']
      elsif meta['phone_number_id'].present?
        "+pn_#{meta['phone_number_id']}"
      else
        "+0000#{SecureRandom.random_number(10**10)}"
      end
    end
  end
end
