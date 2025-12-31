# frozen_string_literal: true

require_relative "../test_helper"

class V18FlagsTest < LarianPak::TestCase
  FIXTURE_PATH = File.expand_path("../fixtures/v18_mixed_compression.pak", __dir__)

  def setup
    super
    @package = LarianPak::Package.read(FIXTURE_PATH)
  end

  def test_compressed_file_has_lz4_flag
    entry = @package.files.find { |f| f.name == "compressed.txt" }

    assert_equal LarianPak::FileEntry::FLAG_LZ4, entry.flags
    assert entry.compressed?
  end

  def test_compressed_file_has_valid_sizes
    entry = @package.files.find { |f| f.name == "compressed.txt" }

    assert entry.uncompressed_size > 0
    assert entry.size_on_disk < entry.uncompressed_size
  end

  def test_uncompressed_file_has_zero_flag
    entry = @package.files.find { |f| f.name == "uncompressed.bin" }

    assert_equal 0, entry.flags
    refute entry.compressed?
  end

  def test_uncompressed_file_has_zero_uncompressed_size
    entry = @package.files.find { |f| f.name == "uncompressed.bin" }

    assert_equal 0, entry.uncompressed_size
    assert entry.size_on_disk > 0
  end

  def test_extract_compressed_file
    content = @package.extract("compressed.txt")

    assert_equal "compress me " * 100, content
  end

  def test_extract_uncompressed_file
    content = @package.extract("uncompressed.bin")

    assert_equal "raw binary data \x00\xFF".b, content
  end
end
