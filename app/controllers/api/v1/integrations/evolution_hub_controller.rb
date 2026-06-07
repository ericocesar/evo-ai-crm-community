require 'httparty'

class Api::V1::Integrations::EvolutionHubController < Api::V1::BaseController
  HUB_API_URL = 'https://api.evohub.ai'

  before_action :ensure_hub_enabled

  def meta_app_options
    response = hub_get('/api/v1/me/meta-app-options')
    return if performed?

    payload = response.is_a?(Hash) ? (response['data'] || {}) : {}
    render json: payload, status: :ok
  end

  def plan
    payload = hub_get('/api/v1/me/plan')
    return if performed?

    render json: payload, status: :ok
  end

  def channels
    payload = hub_get('/api/v1/channels')
    return if performed?

    channels = normalize_channels(payload)
    render json: { channels: channels, count: channels.size }, status: :ok
  end

  def available_channels
    payload = hub_get('/api/v1/channels')
    return if performed?

    channels = normalize_channels(payload)
    channels = channels.reject { |channel| linked_hub_channel_ids.include?(channel['id'].to_s) }

    type_filter = params[:type].to_s
    channels = channels.select { |channel| channel['type'] == type_filter } if type_filter.present?

    render json: { channels: channels, count: channels.size }, status: :ok
  end

  private

  def ensure_hub_enabled
    return if evolution_hub_active?

    render json: { error: 'Evolution Hub não está habilitado neste workspace.' },
           status: :service_unavailable
  end

  def evolution_hub_active?
    enabled = GlobalConfigService.load('EVOLUTION_HUB_ENABLED', 'false').to_s
    ActiveModel::Type::Boolean.new.cast(enabled) && IntegrationRequirements.configured?('evolution_hub')
  end

  def hub_get(path)
    response = HTTParty.get("#{HUB_API_URL}#{path}", headers: hub_headers, timeout: 10)
    return response.parsed_response if response.code.between?(200, 299)

    Rails.logger.error("EvolutionHub proxy GET #{path} failed with HTTP #{response.code}: #{response.body}")
    render json: { error: "Evolution Hub returned HTTP #{response.code}" }, status: :bad_gateway
  rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
    Rails.logger.error("EvolutionHub proxy GET #{path} failed: #{e.class} #{e.message}")
    render json: { error: "Não foi possível alcançar o Hub: #{e.message}" }, status: :bad_gateway
  rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
    Rails.logger.error("EvolutionHub proxy GET #{path} timed out")
    render json: { error: 'Timeout ao conectar ao Hub' }, status: :bad_gateway
  rescue StandardError => e
    Rails.logger.error("EvolutionHub proxy GET #{path} failed unexpectedly: #{e.class} #{e.message}")
    render json: { error: "Falha ao consultar o Hub: #{e.message}" }, status: :bad_gateway
  end

  def hub_headers
    {
      'Authorization' => "Bearer #{GlobalConfigService.load('EVOLUTION_HUB_API_KEY', nil)}",
      'Accept' => 'application/json'
    }
  end

  def normalize_channels(payload)
    raw = if payload.is_a?(Hash)
            data = payload['data']
            payload['channels'] || (data.is_a?(Hash) ? data['channels'] : data) || []
          else
            payload
          end
    return [] unless raw.is_a?(Array)

    raw.select { |channel| channel.is_a?(Hash) }
  end

  def linked_hub_channel_ids
    @linked_hub_channel_ids ||= begin
      ids = Channel::Whatsapp.where("provider_config -> 'evolution_hub' ->> 'channel_id' IS NOT NULL")
                             .pluck(Arel.sql("provider_config -> 'evolution_hub' ->> 'channel_id'"))
      ids += Channel::FacebookPage.where("evolution_hub_meta ->> 'channel_id' IS NOT NULL")
                                  .pluck(Arel.sql("evolution_hub_meta ->> 'channel_id'"))
      ids += Channel::Instagram.where("evolution_hub_meta ->> 'channel_id' IS NOT NULL")
                               .pluck(Arel.sql("evolution_hub_meta ->> 'channel_id'"))
      ids.compact.map(&:to_s).uniq
    end
  end
end
