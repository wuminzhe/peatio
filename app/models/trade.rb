# encoding: UTF-8
# frozen_string_literal: true

class Trade < ApplicationRecord
  include BelongsToMarket
  extend Enumerize
  ZERO = '0.0'.to_d

  enumerize :trend, in: { up: 1, down: 0 }

  belongs_to :ask, class_name: 'OrderAsk', foreign_key: :ask_id, required: true
  belongs_to :bid, class_name: 'OrderBid', foreign_key: :bid_id, required: true
  belongs_to :ask_member, class_name: 'Member', foreign_key: :ask_member_id, required: true
  belongs_to :bid_member, class_name: 'Member', foreign_key: :bid_member_id, required: true

  validates :price, :volume, :funds, numericality: { greater_than_or_equal_to: 0.to_d }

  scope :h24, -> { where('created_at > ?', 24.hours.ago) }

  after_commit on: :create do
    EventAPI.notify ['market', market_id, 'trade_completed'].join('.'), \
      Serializers::EventAPI::TradeCompleted.call(self)
  end


  class << self
    def latest_price(market)
      trade = with_market(market).order(id: :desc).limit(1).first
      trade ? trade.price : 0
    end
  end

  def taker
    ask_id > bid_id ? ask : bid
  end

  def order_fee(order)
    if ask.id == order.id
      ask == taker ? ask.taker_fee : ask.maker_fee
    elsif bid.id == order.id
      bid == taker ? bid.taker_fee : bid.maker_fee
    end
  end

  def side(member)
    return unless member

    self.ask_member_id == member.id ? 'ask' : 'bid'
  end

  def for_notify(member = nil)
    payload = { id:             id,
                side:           side(member),
                kind:           side(member),
                price:          price.to_s  || ZERO,
                volume:         volume.to_s || ZERO,
                market:         market.id,
                at:             created_at.to_i,
                created_at:     created_at.to_i }
    if side(member) == 'ask'
      payload[:ask_id] = ask_id
    else
      payload[:bid_id] = bid_id
    end
    payload
  end

  def for_global
    { tid:        id,
      taker_type: ask_id > bid_id ? :sell : :buy,
      date:       created_at.to_i,
      price:      price.to_s || ZERO,
      amount:     volume.to_s || ZERO }
  end

  def record_complete_operations!
    transaction do
      record_liability_debit!
      record_liability_credit!
      record_liability_transfer!
      record_revenues!
    end
  end

  private
  def record_liability_debit!
    seller_currency_outcome = volume
    buyer_currency_outcome = funds

    # Debit locked fiat/crypto Liability account for member who created ask.
    Operations::Liability.debit!(
      amount:    seller_currency_outcome,
      currency:  ask.currency,
      reference: self,
      kind:      :locked,
      member_id: ask.member_id,
    )
    # Debit locked fiat/crypto Liability account for member who created bid.
    Operations::Liability.debit!(
      amount:    buyer_currency_outcome,
      currency:  bid.currency,
      reference: self,
      kind:      :locked,
      member_id: bid.member_id,
    )
  end

  def record_liability_credit!
    # Fees are related to order type Maker or Taker (not currency).
    seller_currency_income = volume - volume * order_fee(bid)
    buyer_currency_income = funds - funds * order_fee(ask)


    # Credit main fiat/crypto Liability account for member who created ask.
    Operations::Liability.credit!(
      amount:    buyer_currency_income,
      currency:  bid.currency,
      reference: self,
      kind:      :main,
      member_id: ask.member_id
    )

    # Credit main fiat/crypto Liability account for member who created bid.
    Operations::Liability.credit!(
      amount:    seller_currency_income,
      currency:  ask.currency,
      reference: self,
      kind:      :main,
      member_id: bid.member_id
    )
  end

  def record_liability_transfer!
    # Unlock unused funds.
    [bid, ask].each do |order|
      if order.volume.zero? && !order.locked.zero?
        Operations::Liability.transfer!(
          amount:    order.locked,
          currency:  order.currency,
          reference: self,
          from_kind: :locked,
          to_kind:   :main,
          member_id: order.member_id
        )
      end
    end
  end

  def record_revenues!
    seller_currency_fee = volume * order_fee(bid)
    buyer_currency_fee = funds * order_fee(ask)

    # Credit main fiat/crypto Revenue account.
    Operations::Revenue.credit!(
      amount:    seller_currency_fee,
      currency:  ask.currency,
      reference: self,
      member_id: bid.member_id
    )

    # Credit main fiat/crypto Revenue account.
    Operations::Revenue.credit!(
      amount:    buyer_currency_fee,
      currency:  bid.currency,
      reference: self,
      member_id: ask.member_id
    )
  end
end

# == Schema Information
# Schema version: 20190213104708
#
# Table name: trades
#
#  id            :integer          not null, primary key
#  price         :decimal(32, 16)  not null
#  volume        :decimal(32, 16)  not null
#  ask_id        :integer          not null
#  bid_id        :integer          not null
#  trend         :integer          not null
#  market_id     :string(20)       not null
#  ask_member_id :integer          not null
#  bid_member_id :integer          not null
#  funds         :decimal(32, 16)  not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_trades_on_ask_id                           (ask_id)
#  index_trades_on_ask_member_id_and_bid_member_id  (ask_member_id,bid_member_id)
#  index_trades_on_bid_id                           (bid_id)
#  index_trades_on_created_at                       (created_at)
#  index_trades_on_market_id_and_created_at         (market_id,created_at)
#
