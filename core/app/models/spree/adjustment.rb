# Adjustments represent a change to the +item_total+ of an Order. Each adjustment
# has an +amount+ that can be either positive or negative.
#
# Adjustments can be "opened" or "closed".
# Once an adjustment is closed, it will not be automatically updated.
#
# Boolean attributes:
#
# +mandatory+
#
# If this flag is set to true then it means the the charge is required and will not
# be removed from the order, even if the amount is zero. In other words a record
# will be created even if the amount is zero. This is useful for representing things
# such as shipping and tax charges where you may want to make it explicitly clear
# that no charge was made for such things.
#
# +eligible?+
#
# This boolean attributes stores whether this adjustment is currently eligible
# for its order. Only eligible adjustments count towards the order's adjustment
# total. This allows an adjustment to be preserved if it becomes ineligible so
# it might be reinstated.
module Spree
  class Adjustment < Spree::Base
    belongs_to :adjustable, polymorphic: true, touch: true
    belongs_to :source, polymorphic: true
    belongs_to :order, class_name: 'Spree::Order', inverse_of: :all_adjustments

    validates :adjustable, presence: true
    validates :order, presence: true
    validates :label, presence: true
    validates :amount, numericality: true

    after_create :update_adjustable_adjustment_total
    after_destroy :update_adjustable_adjustment_total

    scope :open, -> { where(finalized: false) }
    scope :closed, -> { where(finalized: true) }
    scope :tax, -> { where(source_type: 'Spree::TaxRate') }
    scope :non_tax, -> do
      source_type = arel_table[:source_type]
      where(source_type.not_eq('Spree::TaxRate').or source_type.eq(nil))
    end
    scope :price, -> { where(adjustable_type: 'Spree::LineItem') }
    scope :shipping, -> { where(adjustable_type: 'Spree::Shipment') }
    scope :optional, -> { where(mandatory: false) }
    scope :eligible, -> { where(eligible: true) }
    scope :charge, -> { where("#{quoted_table_name}.amount >= 0") }
    scope :credit, -> { where("#{quoted_table_name}.amount < 0") }
    scope :nonzero, -> { where("#{quoted_table_name}.amount != 0") }
    scope :promotion, -> { where(source_type: 'Spree::PromotionAction') }
    scope :return_authorization, -> { where(source_type: "Spree::ReturnAuthorization") }
    scope :is_included, -> { where(included: true) }
    scope :additional, -> { where(included: false) }

    def closed?
      state == "closed"
    end

    def currency
      adjustable ? adjustable.currency : Spree::Config[:currency]
    end

    def display_amount
      Spree::Money.new(amount, { currency: currency })
    end

    def promotion?
      source.class < Spree::PromotionAction
    end

    def finalize!
      update_attributes!(finalized: true)
    end

    def unfinalize!
      update_attributes!(finalized: false)
    end

    # BEGIN Deprecated methods
    def state
      finalized?? "closed" : "open"
    end

    def state=(new_state)
      case new_state
        when "open"
          self.finalized = false
        when "closed"
          self.finalized = true
        else
          raise "invalid adjustment state #{new_state}"
      end
    end

    def open?
      !closed?
    end

    def closed?
      finalized?
    end

    def open
      unfinalize!
    end
    alias_method :open!, :open

    def close
      finalize!
    end
    alias_method :close!, :close
    # END Deprecated methods

    # Recalculate amount given a target e.g. Order, Shipment, LineItem
    #
    # Passing a target here would always be recommended as it would avoid
    # hitting the database again and would ensure you're compute values over
    # the specific object amount passed here.
    #
    # Noop if the adjustment is locked.
    #
    # If the adjustment has no source, do not attempt to re-calculate the amount.
    # Chances are likely that this was a manually created adjustment in the admin backend.
    def update!(target = nil)
      amount = self.amount
      return amount if finalized?
      if source.present?
        amount = source.compute_amount(target || adjustable)
        self.update_columns(
          amount: amount,
          updated_at: Time.now,
        )
        if promotion?
          self.update_column(:eligible, source.promotion.eligible?(adjustable))
        end
      end
      amount
    end

    private

    def update_adjustable_adjustment_total
      # Cause adjustable's total to be recalculated
      ItemAdjustments.new(adjustable).update
    end

  end
end
