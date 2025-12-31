# frozen_string_literal: true

require_relative "../test_helper"

class V10WriterTest < LarianPak::TestCase
  def test_writes_valid_pak_signature_at_start
    pak_path = File.join(temp_path, "test.pak")

    writer = LarianPak::Versions::V10::Writer.new(pak_path)
    writer.add_file("test.txt", "hello world")
    writer.save

    File.open(pak_path, "rb") do |f|
      assert_equal "LSPK", f.read(4)
    end
  end

  def test_writes_correct_version
    pak_path = File.join(temp_path, "test.pak")

    writer = LarianPak::Versions::V10::Writer.new(pak_path)
    writer.add_file("test.txt", "hello world")
    writer.save

    result = File.open(pak_path, "rb") do |f|
      LarianPak::VersionDetector.detect(f, path: pak_path)
    end

    assert result.valid?
    assert_equal 10, result.version
    assert_equal :start, result.signature_location
  end

  def test_round_trip_single_file
    pak_path = File.join(temp_path, "test.pak")
    content = "hello world"

    writer = LarianPak::Versions::V10::Writer.new(pak_path)
    writer.add_file("test.txt", content)
    writer.save

    package = LarianPak::Package.read(pak_path)

    assert_equal 1, package.files.count
    assert_equal "test.txt", package.files.first.name
    refute package.files.first.compressed?, "V10 stores files uncompressed"

    extracted = package.extract("test.txt")
    assert_equal content, extracted
  end

  def test_round_trip_multiple_files
    pak_path = File.join(temp_path, "test.pak")
    files = {
      "dir/file1.txt" => "content one",
      "dir/file2.txt" => "content two",
      "other/file3.txt" => "content three"
    }

    writer = LarianPak::Versions::V10::Writer.new(pak_path)
    files.each { |name, content| writer.add_file(name, content) }
    writer.save

    package = LarianPak::Package.read(pak_path)

    assert_equal 3, package.files.count
    assert_equal files.keys.sort, package.files.map(&:name).sort

    files.each do |name, expected_content|
      extracted = package.extract(name)
      assert_equal expected_content, extracted, "Content mismatch for #{name}"
    end
  end

  def test_files_stored_uncompressed
    pak_path = File.join(temp_path, "test.pak")
    content = "hello world\n" * 1000

    writer = LarianPak::Versions::V10::Writer.new(pak_path)
    writer.add_file("big.txt", content)
    writer.save

    package = LarianPak::Package.read(pak_path)
    entry = package.files.first

    # V10 stores uncompressed files with flags=0, uncompressed_size=0
    assert_equal 0, entry.flags
    refute entry.compressed?, "V10 should store files uncompressed"
    assert_equal 0, entry.uncompressed_size
    assert_equal content.bytesize, entry.size_on_disk
  end

  def test_add_file_from_path
    pak_path = File.join(temp_path, "test.pak")
    source_path = File.join(temp_path, "source.txt")
    File.write(source_path, "file from disk")

    writer = LarianPak::Versions::V10::Writer.new(pak_path)
    writer.add_file_from_path("archived/source.txt", source_path)
    writer.save

    package = LarianPak::Package.read(pak_path)

    assert_equal 1, package.files.count
    assert_equal "archived/source.txt", package.files.first.name

    extracted = package.extract("archived/source.txt")
    assert_equal "file from disk", extracted
  end
end
