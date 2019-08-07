class UpdateMarketsAskFeeBidFee < ActiveRecord::Migration[5.2]
  def up
    rename_column :markets, :ask_fee, :maker_fee if column_exists?(:markets, :ask_fee)
    rename_column :markets, :bid_fee, :taker_fee if column_exists?(:markets, :bid_fee)
    if column_exists?(:orders, :fee)
      change_column :orders, :fee, :decimal, null: false, default: 0, precision: 17, scale: 16
      rename_column :orders, :fee, :maker_fee
    end
    add_column :orders, :taker_fee, :decimal, null: false, default: 0, precision: 17, scale: 16, after: :maker_fee
    execute('UPDATE orders SET orders.taker_fee = orders.maker_fee')
  end

  def down
    rename_column :markets, :maker_fee, :ask_fee if column_exists?(:markets, :maker_fee)
    rename_column :markets, :taker_fee, :bid_fee if column_exists?(:markets, :taker_fee)
    if column_exists?(:orders, :maker_fee)
      change_column :orders, :maker_fee, :decimal, null: false, default: 0, precision: 32, scale: 16
      rename_column :orders, :maker_fee, :fee
    end
    remove_column :orders, :taker_fee
  end
end
