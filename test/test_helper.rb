# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/larian_pak"

module LarianPak
  class TestCase < Minitest::Test
    def fixtures_path
      File.expand_path("fixtures", __dir__)
    end

    def temp_path
      @temp_path ||= File.expand_path("tmp", __dir__)
    end

    def setup
      FileUtils.mkdir_p(temp_path)
    end

    def teardown
      FileUtils.rm_rf(temp_path) if File.directory?(temp_path)
    end
  end
end
