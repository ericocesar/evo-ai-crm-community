class AddCLeveCustomAttributesAndProducts < ActiveRecord::Migration[7.1]
  def up
    # 1. Create Custom Attribute Definitions for contact_attribute (1)
    attributes = [
      { key: 'tipo_cliente', name: 'Tipo de Cliente', type: :text, description: 'Classificação do cliente (Física ou Jurídica)' },
      { key: 'nome_titular', name: 'Nome do Titular', type: :text, description: 'Nome completo do titular do contrato' },
      { key: 'cpf_titular', name: 'CPF do Titular', type: :text, description: 'CPF (ou CNPJ) do titular da conta' },
      { key: 'data_nascimento_titular', name: 'Data de Nascimento do Titular', type: :text, description: 'Data de nascimento do titular (DD/MM/AAAA)' },
      { key: 'uc_numero', name: 'Número da UC', type: :text, description: 'Número da Unidade Consumidora (UC)' },
      { key: 'concessionaria', name: 'Concessionária', type: :text, description: 'Distribuidora de energia responsável e seu respectivo Estado' },
      { key: 'cep', name: 'CEP', type: :text, description: 'CEP do endereço de instalação (8 dígitos)' },
      { key: 'estado', name: 'Estado (UF)', type: :text, description: 'Sigla do estado (UF) de instalação' },
      { key: 'cidade', name: 'Cidade', type: :text, description: 'Cidade do imóvel de instalação' },
      { key: 'bairro', name: 'bairro', type: :text, description: 'bairro do titular' },
      { key: 'rua', name: 'Rua', type: :text, description: 'Logradouro/Rua do endereço de instalação' },
      { key: 'numero_casa', name: 'Número da Casa', type: :text, description: 'Número do imóvel' },
      { key: 'complemento_endereco', name: 'Complemento do Endereço', type: :text, description: 'Complemento do endereço de instalação' },
      { key: 'valor_medio_conta', name: 'Valor Médio da Conta', type: :currency, description: 'Valor médio da conta de luz' },
      { key: 'economia_mensal', name: 'Economia Mensal', type: :currency, description: 'Valor máximo da economia estimada (15%)' },
      { key: 'ganho', name: 'Ganho', type: :checkbox, description: 'Indica se a oportunidade foi ganha' },
      { key: 'tipo_ligacao', name: 'Tipo de Ligação', type: :text, description: 'Tipo de ligação física da UC' },
      { key: 'interesse_continuar', name: 'Interesse em Continuar', type: :checkbox, description: 'Indica se o cliente tem interesse em continuar' },
      { key: 'qualificacao_energia', name: 'Qualificação Energia', type: :text, description: 'Qualificação do cliente' },
      { key: 'economia_estimada_10', name: 'Economia Estimada (10%)', type: :currency, description: 'Economia estimada de 10%' }
    ]

    attributes.each do |attr|
      # Note: attribute_model enum maps contact_attribute to 1
      unless CustomAttributeDefinition.exists?(attribute_key: attr[:key], attribute_model: 1)
        CustomAttributeDefinition.create!(
          attribute_key: attr[:key],
          attribute_display_name: attr[:name],
          attribute_display_type: attr[:type],
          attribute_model: 1,
          attribute_description: attr[:description]
        )
      end
    end

    # 2. Create the "Energia por assinatura" product if it doesn't exist
    product = Product.find_or_initialize_by(name: "Energia por assinatura")
    if product.new_record?
      product.default_price = 0.0
      product.currency = "BRL"
      product.status = "active"
      product.kind = "digital"
      product.description = "Serviço de energia por assinatura da C Leve."
      product.save!
    end

    # 3. Attach this product to all AI Agents in evo_core_agents table
    if ActiveRecord::Base.connection.table_exists?('evo_core_agents')
      agent_ids = ActiveRecord::Base.connection.select_values("SELECT id FROM evo_core_agents")
      agent_ids.each do |agent_id|
        unless AiAgentProduct.exists?(ai_agent_id: agent_id, product_id: product.id)
          AiAgentProduct.create!(ai_agent_id: agent_id, product_id: product.id)
          
          # Trigger sync to agent config in evo-ai-core-service
          begin
            Ai::AgentProductSyncService.new(ai_agent_id: agent_id).call
          rescue => e
            Rails.logger.warn("Could not sync agent config for agent #{agent_id} in migration: #{e.message}")
          end
        end
      end
    end
  end

  def down
    # Do not destroy to avoid losing user data/configuration on rollback
  end
end
