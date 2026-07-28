# frozen_string_literal: true

module Txnap
  class Railtie < Rails::Railtie
    initializer "txnap.install" do
      ActiveSupport.on_load(:active_record) { Txnap.install! }
    end
  end
end
