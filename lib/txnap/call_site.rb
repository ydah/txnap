# frozen_string_literal: true

module Txnap
  module CallSite
    LIB_ROOT = File.expand_path("..", __dir__)

    module_function

    def capture(locations = caller_locations(2, 80))
      location = locations.find { |candidate| application_location?(candidate) }
      return unless location

      "#{display_path(location)}:#{location.lineno}"
    end

    def application_location?(location)
      path = location.absolute_path || location.path
      return false if path.nil? || path.start_with?(LIB_ROOT)
      return false if path.include?("/gems/activerecord-") || path.include?("/gems/activesupport-")
      return false if path.include?("/gems/bundler-") || path.start_with?("<internal:")

      true
    end

    def display_path(location)
      path = location.absolute_path || location.path
      working_directory = "#{Dir.pwd}/"
      path.start_with?(working_directory) ? path.delete_prefix(working_directory) : path
    end
  end
end
