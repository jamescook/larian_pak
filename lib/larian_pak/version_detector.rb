# frozen_string_literal: true

module LarianPak
  module VersionDetector
    SIGNATURE = "LSPK"
    CONTINUATION_PATTERN = /\A(.+)_(\d+)\.pak\z/i

    Result = Data.define(:status, :version, :signature_location, :parent_path, :part_number) do
      def valid? = status == :ok
      def continuation? = status == :continuation
    end

    # Detect PAK version by checking signature location and version field
    # Returns Result with status :ok, :continuation, or :invalid
    def self.detect(io, path: nil)
      file_size = io.size

      # Check end of file first (V13 has signature at end)
      if file_size >= 8
        io.seek(-4, IO::SEEK_END)
        if io.read(4) == SIGNATURE
          io.seek(-8, IO::SEEK_END)
          header_size = io.read(4).unpack1("V")

          io.seek(-header_size, IO::SEEK_END)
          version = io.read(4).unpack1("V")

          return Result.new(status: :ok, version: version, signature_location: :end,
                           parent_path: nil, part_number: nil)
        end
      end

      # Check start of file (V10/V15/V16/V18 have signature at start)
      io.seek(0)
      if io.read(4) == SIGNATURE
        version = io.read(4).unpack1("V")
        return Result.new(status: :ok, version: version, signature_location: :start,
                         parent_path: nil, part_number: nil)
      end

      # Check for V7/V9 (no signature, version number at offset 0)
      io.seek(0)
      version = io.read(4).unpack1("V")
      if version == 7 || version == 9
        return Result.new(status: :ok, version: version, signature_location: :none,
                         parent_path: nil, part_number: nil)
      end

      # No valid header - check if it's a verified continuation file
      if path && (continuation = verify_continuation(path))
        return Result.new(status: :continuation, version: nil, signature_location: nil,
                         parent_path: continuation[:parent_path], part_number: continuation[:part_number])
      end

      Result.new(status: :invalid, version: nil, signature_location: nil,
                parent_path: nil, part_number: nil)
    end

    # Check if file is a continuation by verifying parent references it
    def self.verify_continuation(path)
      filename = File.basename(path)
      match = CONTINUATION_PATTERN.match(filename)
      return nil unless match

      base_name = match[1]
      part_number = match[2].to_i
      parent_path = File.join(File.dirname(path), "#{base_name}.pak")

      return nil unless File.exist?(parent_path)

      # Read parent and check if any entries reference this part number
      File.open(parent_path, "rb") do |parent_io|
        parent_result = detect(parent_io, path: nil)
        return nil unless parent_result.valid?

        reader = Package.reader_for_version(parent_result.version)
        parent_pkg = reader.read(parent_io, parent_path, parent_result.signature_location)

        has_reference = parent_pkg.files.any? { |f| f.archive_part == part_number }
        return nil unless has_reference

        { parent_path: parent_path, part_number: part_number }
      end
    end

    # Convenience method that raises on invalid (old behavior)
    def self.detect!(io, path: nil)
      result = detect(io, path: path)

      case result.status
      when :ok
        [result.version, result.signature_location]
      when :continuation
        raise InvalidSignature, "File is a multi-part continuation of #{File.basename(result.parent_path)} (part #{result.part_number})"
      else
        raise InvalidSignature, "No LSPK signature found"
      end
    end
  end
end
