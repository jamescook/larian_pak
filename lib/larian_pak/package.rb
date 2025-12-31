# frozen_string_literal: true

require "extlz4"
require "fileutils"

module LarianPak
  class Package
    attr_reader :version, :files, :path, :flags

    def initialize(version:, files:, path: nil, flags: 0)
      @version = version
      @files = files
      @path = path
      @flags = flags
    end

    def self.read(path)
      File.open(path, "rb") do |io|
        version, sig_location = VersionDetector.detect!(io, path: path)
        reader = reader_for_version(version)
        reader.read(io, path, sig_location)
      end
    end

    def self.reader_for_version(version)
      case version
      when 7, 9
        Versions::V9
      when 10
        Versions::V10
      when 13
        Versions::V13
      when 15, 16, 18
        Versions::V18
      else
        raise UnsupportedVersion, "PAK version #{version} is not supported"
      end
    end

    def file_count
      files.count
    end

    def find(name)
      files.find { |f| f.name == name }
    end

    def list
      files.map(&:name)
    end

    # Extract a single file's contents
    def extract(entry)
      entry = find(entry) if entry.is_a?(String)
      raise Error, "File not found" unless entry

      # Handle empty files
      return "".b if entry.size_on_disk.zero?

      pak_path = path_for_part(entry.archive_part)
      File.open(pak_path, "rb") do |io|
        io.seek(entry.offset)
        data = io.read(entry.size_on_disk)

        if entry.compressed?
          LZ4.block_decode(data, entry.uncompressed_size)
        else
          data
        end
      end
    end

    # Extract all files to a directory
    def extract_all(output_dir)
      files.each do |entry|
        output_path = File.join(output_dir, entry.name)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.binwrite(output_path, extract(entry))
      end
    end

    private

    def path_for_part(part)
      return path if part == 0

      dir = File.dirname(path)
      base = File.basename(path, ".pak")
      File.join(dir, "#{base}_#{part}.pak")
    end
  end
end
