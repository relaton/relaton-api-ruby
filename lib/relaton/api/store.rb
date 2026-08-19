# frozen_string_literal: true

module Relaton
  module Api
    # Store namespace; children declared here.
    module Store
      autoload :FileSystem, "relaton/api/store/file_system"
    end
  end
end
