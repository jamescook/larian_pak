# frozen_string_literal: true

require_relative "larian_pak/version_detector"
require_relative "larian_pak/file_entry"
require_relative "larian_pak/package"
require_relative "larian_pak/versions/v9"
require_relative "larian_pak/versions/v10"
require_relative "larian_pak/versions/v13"
require_relative "larian_pak/versions/v18"

module LarianPak
  class Error < StandardError; end
  class InvalidSignature < Error; end
  class UnsupportedVersion < Error; end
end
