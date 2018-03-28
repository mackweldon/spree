module Spree
  module Api
    module ControllerSetup
      def self.included(klass)
        klass.class_eval do
          include CanCan::ControllerAdditions
          include Spree::Core::ControllerHelpers::Auth

          prepend_view_path Rails.root + "app/views"
          append_view_path File.expand_path("../../../app/views", File.dirname(__FILE__))

          respond_to :json
        end
      end
    end
  end
end
