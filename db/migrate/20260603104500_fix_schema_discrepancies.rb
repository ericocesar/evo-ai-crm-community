class FixSchemaDiscrepancies < ActiveRecord::Migration[7.0]
  def change
    # 1. contact_inboxes
    unless column_exists?(:contact_inboxes, :bsuid)
      add_column :contact_inboxes, :bsuid, :text
    end
    unless column_exists?(:contact_inboxes, :whatsapp_username)
      add_column :contact_inboxes, :whatsapp_username, :text
    end
    unless index_exists?(:contact_inboxes, [:inbox_id, :bsuid], name: 'index_contact_inboxes_on_inbox_id_and_bsuid')
      add_index :contact_inboxes, %i[inbox_id bsuid], unique: true, where: 'bsuid IS NOT NULL', name: 'index_contact_inboxes_on_inbox_id_and_bsuid'
    end

    # 2. attachments
    unless column_exists?(:attachments, :attachable_type)
      add_column :attachments, :attachable_type, :string
    end
    unless column_exists?(:attachments, :attachable_id)
      add_column :attachments, :attachable_id, :uuid
    end
    unless index_exists?(:attachments, [:attachable_type, :attachable_id], name: 'index_attachments_on_attachable_type_and_attachable_id')
      add_index :attachments, [:attachable_type, :attachable_id], name: 'index_attachments_on_attachable_type_and_attachable_id'
    end

    # Migrate any data from message_id to attachable if message_id exists
    if column_exists?(:attachments, :message_id)
      execute <<-SQL
        UPDATE attachments
        SET attachable_type = 'Message',
            attachable_id = message_id
        WHERE message_id IS NOT NULL AND attachable_type IS NULL;
      SQL
      remove_column :attachments, :message_id
    end

    # 3. channel_email
    unless column_exists?(:channel_email, :email_signature)
      add_column :channel_email, :email_signature, :text
    end

    # 4. channel_web_widgets
    unless column_exists?(:channel_web_widgets, :locale)
      add_column :channel_web_widgets, :locale, :string
    end

    # 5. pipeline_stages
    unless column_exists?(:pipeline_stages, :custom_fields)
      add_column :pipeline_stages, :custom_fields, :jsonb, default: {}, null: false
      add_index :pipeline_stages, :custom_fields, name: 'index_pipeline_stages_on_custom_fields', using: :gin
    end

    # 6. pipelines
    unless column_exists?(:pipelines, :custom_fields)
      add_column :pipelines, :custom_fields, :jsonb, default: {}, null: false
      add_index :pipelines, :custom_fields, name: 'index_pipelines_on_custom_fields', using: :gin
    end
    unless column_exists?(:pipelines, :is_default)
      add_column :pipelines, :is_default, :boolean, default: false, null: false
      add_index :pipelines, :is_default, name: 'index_pipelines_on_is_default_unique', where: 'is_default = true'
    end

    # 7. stage_movements
    unless column_exists?(:stage_movements, :pipeline_item_id)
      add_column :stage_movements, :pipeline_item_id, :uuid
      add_index :stage_movements, :pipeline_item_id, name: 'index_stage_movements_on_pipeline_item_id'
    end
  end
end
