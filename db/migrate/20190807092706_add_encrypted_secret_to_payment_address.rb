class AddEncryptedSecretToPaymentAddress < ActiveRecord::Migration[5.2]
  def up
    secrets = PaymentAddress.pluck(:id, :secret)
    # details = PaymentAddress.pluck(:id, :details)
    # settings = Wallet.pluck(:id, :settings)

    remove_column :payment_addresses, :secret
    add_column :payment_addresses, :secret_encrypted , :string, after: :address

    remove_column :payment_addresses, :details
    add_column :payment_addresses, :details_encrypted , :string, after: :secret_encrypted

    remove_column :wallets, :settings
    add_column :wallets, :settings_encrypted , :string, after: :status

    secrets.each do |s|
      atr = PaymentAddress.__vault_attributes[:secret]
      enc = Vault::Rails.encrypt(atr[:path], atr[:key], s[1])
      # PaymentAddress.find(s[0]).update!(secret: s[1])
      execute "UPDATE payment_addresses SET secret_encrypted = #{enc} WHERE id = #{s[0]}"
    end
    # details.each { |s| PaymentAddress.find(s[0]).update(details_encrypted: s[1]) }
    # settings.each { |s| Wallet.find(s[0]).update(settings_encrypted: s[1]) }
  end

end
