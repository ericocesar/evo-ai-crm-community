require 'rails_helper'

RSpec.describe EvoHub::InboxBuilder do
  describe '#perform' do
    let(:client) { instance_double(EvoHub::Client) }
    let(:channel) do
      Channel::Instagram.new(
        id: SecureRandom.uuid,
        access_token: '',
        instagram_id: 'pending_test',
        expires_at: 60.days.from_now,
        evolution_hub_meta: { 'status' => 'pending' }
      )
    end
    let(:inbox) { instance_double(Inbox) }
    let(:builder) { described_class.new(channel_type: 'instagram', name: 'Instagram Hub') }

    before do
      @previous_backend_url = ENV['BACKEND_URL']
      allow(builder).to receive(:client).and_return(client)
      allow(builder).to receive(:build_instagram).and_return(channel)
      allow(channel).to receive(:update!)
      allow(Inbox).to receive(:create!).and_return(inbox)
      allow(GlobalConfigService).to receive(:load)
      allow(GlobalConfigService).to receive(:load).with('EVOLUTION_HUB_WEBHOOK_SECRET', nil).and_return('secret')
      ENV['BACKEND_URL'] = 'https://crm.test'
    end

    after do
      @previous_backend_url.nil? ? ENV.delete('BACKEND_URL') : ENV['BACKEND_URL'] = @previous_backend_url
    end

    it 'creates the webhook explicitly when Evo Hub single-shot omits webhook_id' do
      allow(client).to receive(:create_channel).and_return(
        {
          'channel' => {
            'id' => 'hub-channel-id',
            'token' => 'hub-channel-token',
            'type' => 'instagram',
            'name' => 'Instagram Hub',
            'status' => 'inactive'
          }
        }
      )
      allow(client).to receive(:create_webhook).and_return({ 'id' => 'hub-webhook-id' })

      result = builder.perform

      expect(client).to have_received(:create_webhook).with(
        name: 'EvoCRM - Instagram Hub',
        url: 'https://crm.test/webhooks/evolution_hub',
        events: described_class::WEBHOOK_EVENTS,
        secret: 'secret',
        channels: ['hub-channel-id']
      )
      expect(channel).to have_received(:update!).with(
        evolution_hub_meta: hash_including(
          'channel_id' => 'hub-channel-id',
          'channel_token' => 'hub-channel-token',
          'webhook_id' => 'hub-webhook-id',
          'public_link' => 'https://app.evohub.evolutionfoundation.com.br/connect/hub-channel-token',
          'status' => 'pending'
        )
      )
      expect(result).to eq(
        inbox: inbox,
        public_link: 'https://app.evohub.evolutionfoundation.com.br/connect/hub-channel-token'
      )
    end
  end
end
