require 'openssl'

class Webhooks::EvolutionHubController < ActionController::API
  def create
    return unless verify_signature!

    payload = JSON.parse(request.raw_post)
    event = payload['event'] || payload['event_type']

    case event
    when 'channel_connected'
      mark_channel_connected(payload)
    when 'channel_disconnected'
      mark_channel_disconnected(payload)
    else
      Rails.logger.info("EvoHub webhook ignored event=#{event.inspect}")
    end

    head :ok
  rescue JSON::ParserError => e
    Rails.logger.error("EvoHub webhook parse error: #{e.message}")
    head :bad_request
  rescue StandardError => e
    Rails.logger.error("EvoHub webhook error: #{e.class} #{e.message}")
    Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    head :internal_server_error
  end

  private

  def verify_signature!
    secret = GlobalConfigService.load('EVOLUTION_HUB_WEBHOOK_SECRET', nil).to_s
    if secret.blank?
      head :unauthorized
      return false
    end

    provided = request.headers['X-Hub-Signature-256'].to_s
    unless provided.start_with?('sha256=')
      head :unauthorized
      return false
    end

    expected = "sha256=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, request.raw_post)}"
    return true if expected.bytesize == provided.bytesize &&
                   ActiveSupport::SecurityUtils.secure_compare(expected, provided)

    head :unauthorized
    false
  end

  def mark_channel_connected(payload)
    channel = find_local_channel(payload)
    return Rails.logger.warn("EvoHub channel_connected without local channel: #{payload.inspect[0, 500]}") unless channel

    meta = payload['meta_connection'] || {}
    hub_block = hub_block_from(channel, payload).merge('status' => 'active')

    case channel
    when Channel::Whatsapp
      provider_config = (channel.provider_config || {}).deep_dup
      provider_config['api_key'] = meta['access_token'] if meta['access_token'].present?
      provider_config['phone_number_id'] = meta['phone_number_id'] if meta['phone_number_id'].present?
      provider_config['waba_id'] = meta['waba_id'] if meta['waba_id'].present?
      provider_config['business_account_id'] = meta['waba_id'] if meta['waba_id'].present?
      provider_config['evolution_hub'] = hub_block
      channel.update!(provider_config: provider_config)
    when Channel::FacebookPage
      channel.page_id = meta['page_id'] if meta['page_id'].present?
      channel.page_access_token = meta['access_token'] if meta['access_token'].present?
      channel.evolution_hub_meta = hub_block
      channel.save!
    when Channel::Instagram
      channel.instagram_id = meta['instagram_user_id'] if meta['instagram_user_id'].present?
      channel.access_token = meta['access_token'] if meta['access_token'].present?
      channel.evolution_hub_meta = hub_block
      channel.save!
    end
  end

  def mark_channel_disconnected(payload)
    channel = find_local_channel(payload)
    return unless channel

    if channel.is_a?(Channel::Whatsapp)
      provider_config = (channel.provider_config || {}).deep_dup
      provider_config['evolution_hub'] = hub_block_from(channel, payload).merge('status' => 'inactive')
      channel.update!(provider_config: provider_config)
    else
      channel.update!(evolution_hub_meta: hub_block_from(channel, payload).merge('status' => 'inactive'))
    end
  end

  def find_local_channel(payload)
    external_id = (payload['external_id'] || payload.dig('channel', 'external_id')).to_s
    if external_id.present?
      [Channel::Whatsapp, Channel::FacebookPage, Channel::Instagram].each do |klass|
        record = klass.find_by(id: external_id)
        return record if record
      end
    end

    hub_channel_id = (payload['channel_id'] || payload.dig('channel', 'id')).to_s
    return nil if hub_channel_id.blank?

    Channel::Whatsapp.where("provider_config -> 'evolution_hub' ->> 'channel_id' = ?", hub_channel_id).first ||
      Channel::FacebookPage.where("evolution_hub_meta ->> 'channel_id' = ?", hub_channel_id).first ||
      Channel::Instagram.where("evolution_hub_meta ->> 'channel_id' = ?", hub_channel_id).first
  end

  def hub_block_from(channel, payload)
    existing =
      if channel.is_a?(Channel::Whatsapp)
        (channel.provider_config || {}).dig('evolution_hub') || {}
      else
        channel.evolution_hub_meta || {}
      end

    existing.merge(
      'channel_id' => payload['channel_id'] || payload.dig('channel', 'id') || existing['channel_id'],
      'channel_token' => payload['channel_token'] || payload.dig('channel', 'token') || existing['channel_token']
    )
  end
end
