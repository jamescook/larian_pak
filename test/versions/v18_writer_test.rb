# frozen_string_literal: true

require_relative "../test_helper"

class V18WriterTest < LarianPak::TestCase
  def test_writes_valid_pak_signature_at_start
    pak_path = File.join(temp_path, "test.pak")

    writer = LarianPak::Versions::V18::Writer.new(pak_path)
    writer.add_file("test.txt", "hello world")
    writer.save

    # V18 has signature at start of file
    File.open(pak_path, "rb") do |f|
      assert_equal "LSPK", f.read(4)
    end
  end

  def test_writes_correct_version
    pak_path = File.join(temp_path, "test.pak")

    writer = LarianPak::Versions::V18::Writer.new(pak_path)
    writer.add_file("test.txt", "hello world")
    writer.save

    result = File.open(pak_path, "rb") do |f|
      LarianPak::VersionDetector.detect(f, path: pak_path)
    end

    assert result.valid?
    assert_equal 18, result.version
    assert_equal :start, result.signature_location
  end

  def test_round_trip_single_file
    pak_path = File.join(temp_path, "test.pak")
    content = "hello world"

    writer = LarianPak::Versions::V18::Writer.new(pak_path)
    writer.add_file("test.txt", content)
    writer.save

    package = LarianPak::Package.read(pak_path)

    assert_equal 1, package.files.count
    assert_equal "test.txt", package.files.first.name
    assert_equal content.bytesize, package.files.first.uncompressed_size
  end

  def test_round_trip_multiple_files
    pak_path = File.join(temp_path, "test.pak")
    files = {
      "dir/file1.txt" => "content one",
      "dir/file2.txt" => "content two",
      "other/file3.txt" => "content three"
    }

    writer = LarianPak::Versions::V18::Writer.new(pak_path)
    files.each { |name, content| writer.add_file(name, content) }
    writer.save

    package = LarianPak::Package.read(pak_path)

    assert_equal 3, package.files.count
    assert_equal files.keys.sort, package.files.map(&:name).sort

    files.each do |name, content|
      entry = package.find(name)
      assert entry, "Expected to find #{name}"
      assert_equal content.bytesize, entry.uncompressed_size
    end
  end

  def test_round_trip_with_compression
    pak_path = File.join(temp_path, "test.pak")
    content = "hello world\n" * 1000

    writer = LarianPak::Versions::V18::Writer.new(pak_path)
    writer.add_file("compressible.txt", content)
    writer.save

    package = LarianPak::Package.read(pak_path)
    entry = package.files.first

    assert entry.compressed?, "Expected file to be compressed"
    assert entry.size_on_disk < entry.uncompressed_size
  end
end

class V18ExtractionTest < LarianPak::TestCase
  def fixture_data(name)
    File.binread(File.join(fixtures_path, name))
  end

  def test_extract_single_file_content_matches
    pak_path = File.join(temp_path, "test.pak")
    original_content = "hello world, this is test content"

    writer = LarianPak::Versions::V18::Writer.new(pak_path)
    writer.add_file("test.txt", original_content)
    writer.save

    package = LarianPak::Package.read(pak_path)
    extracted = package.extract("test.txt")

    assert_equal original_content, extracted
  end

  def test_extract_compressed_file_content_matches
    pak_path = File.join(temp_path, "test.pak")
    original_content = "repeated content\n" * 500

    writer = LarianPak::Versions::V18::Writer.new(pak_path)
    writer.add_file("big.txt", original_content)
    writer.save

    package = LarianPak::Package.read(pak_path)
    entry = package.find("big.txt")

    assert entry.compressed?
    extracted = package.extract(entry)
    assert_equal original_content, extracted
  end

  def test_extract_binary_file_content_matches
    pak_path = File.join(temp_path, "test.pak")
    original_content = fixture_data("random_600a.bin")

    writer = LarianPak::Versions::V18::Writer.new(pak_path)
    writer.add_file("data.bin", original_content)
    writer.save

    package = LarianPak::Package.read(pak_path)
    extracted = package.extract("data.bin")

    assert_equal original_content, extracted
  end

  def test_extract_fixture_files_round_trip
    pak_path = File.join(temp_path, "test.pak")
    files = {
      "config/settings.json" => fixture_data("sample_config.json"),
      "data/info.lsx" => fixture_data("sample_data.lsx"),
      "docs/readme.txt" => fixture_data("sample_text.txt")
    }

    writer = LarianPak::Versions::V18::Writer.new(pak_path)
    files.each { |name, content| writer.add_file(name, content) }
    writer.save

    package = LarianPak::Package.read(pak_path)

    files.each do |name, original_content|
      extracted = package.extract(name)
      assert_equal original_content, extracted, "Content mismatch for #{name}"
    end
  end

  def test_extract_random_access_last_file
    pak_path = File.join(temp_path, "test.pak")

    writer = LarianPak::Versions::V18::Writer.new(pak_path)
    50.times { |i| writer.add_file("padding/file#{i}.txt", "padding content #{i}" * 100) }
    writer.add_file("target/last.txt", "THIS IS THE TARGET FILE")
    writer.save

    package = LarianPak::Package.read(pak_path)

    extracted = package.extract("target/last.txt")
    assert_equal "THIS IS THE TARGET FILE", extracted
  end
end
