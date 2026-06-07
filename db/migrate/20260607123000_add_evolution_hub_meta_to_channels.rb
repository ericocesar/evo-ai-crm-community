class AddEvolutionHubMetaToChannels < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_facebook_pages, :evolution_hub_meta, :jsonb, default: {}, null: false
    add_column :channel_instagram, :evolution_hub_meta, :jsonb, default: {}, null: false
  end
end
