# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"

class V13WriterTest < LarianPak::TestCase
  def test_writes_valid_pak_signature_at_end
    pak_path = File.join(temp_path, "test.pak")

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
    writer.add_file("test.txt", "hello world")
    writer.save

    # V13 has signature at end of file
    File.open(pak_path, "rb") do |f|
      f.seek(-4, IO::SEEK_END)
      assert_equal "LSPK", f.read(4)
    end
  end

  def test_writes_correct_version
    pak_path = File.join(temp_path, "test.pak")

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
    writer.add_file("test.txt", "hello world")
    writer.save

    result = File.open(pak_path, "rb") do |f|
      LarianPak::VersionDetector.detect(f, path: pak_path)
    end

    assert result.valid?
    assert_equal 13, result.version
    assert_equal :end, result.signature_location
  end

  def test_round_trip_single_file
    pak_path = File.join(temp_path, "test.pak")
    content = "hello world"

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
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

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
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
    # Repetitive content compresses well
    content = "hello world\n" * 1000

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
    writer.add_file("compressible.txt", content)
    writer.save

    package = LarianPak::Package.read(pak_path)
    entry = package.files.first

    assert entry.compressed?, "Expected file to be compressed"
    assert entry.size_on_disk < entry.uncompressed_size
  end

  def test_round_trip_empty_file
    pak_path = File.join(temp_path, "test.pak")

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
    writer.add_file("empty.txt", "")
    writer.save

    package = LarianPak::Package.read(pak_path)

    assert_equal 1, package.files.count
    assert_equal 0, package.files.first.uncompressed_size

    # Verify extraction works for empty files
    extracted = package.extract("empty.txt")
    assert_equal "", extracted
  end

  def test_add_file_from_path
    pak_path = File.join(temp_path, "test.pak")
    source_path = File.join(temp_path, "source.txt")
    File.write(source_path, "file from disk")

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
    writer.add_file_from_path("archived/source.txt", source_path)
    writer.save

    package = LarianPak::Package.read(pak_path)

    assert_equal 1, package.files.count
    assert_equal "archived/source.txt", package.files.first.name
  end
end

class V13ExtractionTest < LarianPak::TestCase
  def fixture_data(name)
    File.binread(File.join(fixtures_path, name))
  end

  def test_extract_single_file_content_matches
    pak_path = File.join(temp_path, "test.pak")
    original_content = "hello world, this is test content"

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
    writer.add_file("test.txt", original_content)
    writer.save

    package = LarianPak::Package.read(pak_path)
    extracted = package.extract("test.txt")

    assert_equal original_content, extracted
  end

  def test_extract_compressed_file_content_matches
    pak_path = File.join(temp_path, "test.pak")
    original_content = "repeated content\n" * 500

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
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

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
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

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
    files.each { |name, content| writer.add_file(name, content) }
    writer.save

    package = LarianPak::Package.read(pak_path)

    files.each do |name, original_content|
      extracted = package.extract(name)
      assert_equal original_content, extracted, "Content mismatch for #{name}"
    end
  end

  def test_extract_all_to_directory
    pak_path = File.join(temp_path, "test.pak")
    output_dir = File.join(temp_path, "extracted")
    files = {
      "dir1/file1.txt" => "content one",
      "dir2/file2.txt" => "content two"
    }

    writer = LarianPak::Versions::V13::Writer.new(pak_path)
    files.each { |name, content| writer.add_file(name, content) }
    writer.save

    package = LarianPak::Package.read(pak_path)
    package.extract_all(output_dir)

    files.each do |name, original_content|
      extracted_path = File.join(output_dir, name)
      assert File.exist?(extracted_path), "Expected #{extracted_path} to exist"
      assert_equal original_content, File.read(extracted_path)
    end
  end

  def test_extract_random_access_last_file
    pak_path = File.join(temp_path, "test.pak")

    # Create PAK with many files
    writer = LarianPak::Versions::V13::Writer.new(pak_path)
    50.times { |i| writer.add_file("padding/file#{i}.txt", "padding content #{i}" * 100) }
    writer.add_file("target/last.txt", "THIS IS THE TARGET FILE")
    writer.save

    package = LarianPak::Package.read(pak_path)

    # Extract only the last file - should seek directly, not read through others
    extracted = package.extract("target/last.txt")
    assert_equal "THIS IS THE TARGET FILE", extracted
  end
end

class V13MultiPartExtractionTest < LarianPak::TestCase
  def fixture_data(name)
    File.binread(File.join(fixtures_path, name))
  end

  def test_extract_from_continuation_file
    pak_path = File.join(temp_path, "test.pak")

    # Create multi-part PAK with incompressible data
    writer = LarianPak::Versions::V13::Writer.new(pak_path, max_part_size: 1000)
    file1_content = fixture_data("random_600a.bin")
    file2_content = fixture_data("random_600b.bin")
    file3_content = fixture_data("random_600c.bin")

    writer.add_file("part0/file1.bin", file1_content)
    writer.add_file("part1/file2.bin", file2_content)
    writer.add_file("part1/file3.bin", file3_content)
    writer.save

    package = LarianPak::Package.read(pak_path)

    # Find a file in part 1 (continuation)
    entry_in_continuation = package.files.find { |f| f.archive_part > 0 }
    assert entry_in_continuation, "Expected at least one file in continuation"

    # Extract it - should read from test_1.pak
    extracted = package.extract(entry_in_continuation)

    # Verify content matches
    expected = entry_in_continuation.name.include?("file2") ? file2_content : file3_content
    assert_equal expected, extracted
  end
end

class V13WriterMultiPartTest < LarianPak::TestCase
  def fixture_data(name)
    File.binread(File.join(fixtures_path, name))
  end

  def test_writes_continuation_files_when_exceeds_max_size
    pak_path = File.join(temp_path, "test.pak")

    # Use incompressible fixture data to force multi-part
    writer = LarianPak::Versions::V13::Writer.new(pak_path, max_part_size: 1000)
    writer.add_file("file1.bin", fixture_data("random_600a.bin"))
    writer.add_file("file2.bin", fixture_data("random_600b.bin"))
    writer.add_file("file3.bin", fixture_data("random_600c.bin"))
    writer.save

    assert File.exist?(pak_path), "Main pak should exist"
    assert File.exist?(File.join(temp_path, "test_1.pak")), "Continuation should exist"

    # Main pak should be readable
    package = LarianPak::Package.read(pak_path)
    assert_equal 3, package.files.count

    # Should have files in different parts
    parts = package.files.map(&:archive_part).uniq.sort
    assert parts.length > 1, "Expected files in multiple parts, got: #{parts.inspect}"
  end

  def test_continuation_files_detected_correctly
    pak_path = File.join(temp_path, "test.pak")
    cont_path = File.join(temp_path, "test_1.pak")

    writer = LarianPak::Versions::V13::Writer.new(pak_path, max_part_size: 1000)
    writer.add_file("file1.bin", fixture_data("random_600a.bin"))
    writer.add_file("file2.bin", fixture_data("random_600b.bin"))
    writer.add_file("file3.bin", fixture_data("random_600c.bin"))
    writer.save

    assert File.exist?(cont_path), "Continuation file must exist"

    result = File.open(cont_path, "rb") do |f|
      LarianPak::VersionDetector.detect(f, path: cont_path)
    end

    assert result.continuation?
    assert_equal pak_path, result.parent_path
    assert_equal 1, result.part_number
  end
end

