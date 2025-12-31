# frozen_string_literal: true

require "extlz4"

module LarianPak
  module Versions
    # Reader for PAK versions 10 and 13 (DOS2, DOS1:EE uses V13)
    #
    # V13 has signature at END of file:
    #   [file data]
    #   [compressed file list]
    #   [header - 32 bytes]
    #   [header_size - 4 bytes]
    #   [LSPK signature - 4 bytes]
    #
    # Header structure (32 bytes):
    #   UInt32    Version
    #   UInt32    FileListOffset
    #   UInt32    FileListSize (compressed)
    #   UInt16    NumParts
    #   Byte      Flags
    #   Byte      Priority
    #   Byte[16]  MD5
    #
    # File entry structure (280 bytes):
    #   Byte[256]  Name (null-terminated)
    #   UInt32     OffsetInFile
    #   UInt32     SizeOnDisk
    #   UInt32     UncompressedSize
    #   UInt32     ArchivePart
    #   UInt32     Flags
    #   UInt32     Crc
    #
    module V13
      HEADER_SIZE = 32
      FILE_ENTRY_SIZE = 280
      NAME_SIZE = 256

      Header = Data.define(
        :version, :file_list_offset, :file_list_size,
        :num_parts, :flags, :priority, :md5
      )

      def self.read(io, path, sig_location)
        header = read_header(io)
        files = read_file_entries(io, header)

        Package.new(
          version: header.version,
          files: files,
          path: path,
          flags: header.flags
        )
      end

      def self.read_header(io)
        # Seek to header position (file_size - 8 - HEADER_SIZE)
        io.seek(-8, IO::SEEK_END)
        header_size = io.read(4).unpack1("V")

        io.seek(-header_size, IO::SEEK_END)
        data = io.read(HEADER_SIZE)

        values = data.unpack("V V V v C C a16")
        Header.new(
          version: values[0],
          file_list_offset: values[1],
          file_list_size: values[2],
          num_parts: values[3],
          flags: values[4],
          priority: values[5],
          md5: values[6]
        )
      end

      def self.read_file_entries(io, header)
        io.seek(header.file_list_offset)

        # First 4 bytes are the number of files
        num_files = io.read(4).unpack1("V")

        # Rest is LZ4-compressed file entry data
        compressed_size = header.file_list_size - 4
        compressed_data = io.read(compressed_size)

        expected_size = num_files * FILE_ENTRY_SIZE
        decompressed = LZ4.block_decode(compressed_data, expected_size)

        entries = []
        num_files.times do |i|
          offset = i * FILE_ENTRY_SIZE
          entry_data = decompressed[offset, FILE_ENTRY_SIZE]

          name = entry_data[0, NAME_SIZE].unpack1("Z*")
          file_offset, size_on_disk, uncompressed_size, archive_part, flags, _crc =
            entry_data[NAME_SIZE, 24].unpack("V V V V V V")

          entries << FileEntry.new(
            name: name,
            offset: file_offset,
            size_on_disk: size_on_disk,
            uncompressed_size: uncompressed_size,
            archive_part: archive_part,
            flags: flags
          )
        end

        entries
      end

      # Writer for V13 PAK files
      class Writer
        VERSION = 13
        SIGNATURE = "LSPK"
        COMPRESSION_FLAG_LZ4 = 0x02

        PendingFile = Data.define(:name, :content, :uncompressed_size, :compress)

        def initialize(path, max_part_size: nil)
          @path = path
          @max_part_size = max_part_size
          @pending_files = []
        end

        def add_file(name, content, compress: true)
          content = content.b # ensure binary
          @pending_files << PendingFile.new(
            name: name,
            content: content,
            uncompressed_size: content.bytesize,
            compress: compress
          )
        end

        def add_file_from_path(name, source_path, compress: true)
          add_file(name, File.binread(source_path), compress: compress)
        end

        def save
          if @max_part_size
            save_multipart
          else
            save_single
          end
        end

        private

        def save_single
          File.open(@path, "wb") do |io|
            entries = write_file_data(io, @pending_files, 0)
            write_footer(io, entries, 1)
          end
        end

        def save_multipart
          entries = []
          part = 0
          part_io = nil
          part_path = nil
          current_part_size = 0

          begin
            @pending_files.each do |pending|
              if pending.compress
                data = compress(pending.content)
                flags = COMPRESSION_FLAG_LZ4
              else
                data = pending.content
                flags = 0
              end

              # Check if we need a new part
              if part_io.nil? || (current_part_size + data.bytesize > @max_part_size && current_part_size > 0)
                part_io&.close
                part += 1 if part_io
                part_path = part == 0 ? @path : continuation_path(part)
                part_io = File.open(part_path, "wb")
                current_part_size = 0
              end

              offset = part_io.pos
              part_io.write(data)
              current_part_size += data.bytesize

              entries << build_entry(pending, offset, data.bytesize, part, flags)
            end
          ensure
            part_io&.close
          end

          # Write footer to main file
          File.open(@path, "r+b") do |io|
            io.seek(0, IO::SEEK_END)
            write_footer(io, entries, part + 1)
          end
        end

        def write_file_data(io, pending_files, part)
          pending_files.map do |pending|
            offset = io.pos
            if pending.compress
              data = compress(pending.content)
              flags = COMPRESSION_FLAG_LZ4
            else
              data = pending.content
              flags = 0
            end
            io.write(data)
            build_entry(pending, offset, data.bytesize, part, flags)
          end
        end

        def build_entry(pending, offset, size_on_disk, archive_part, flags)
          FileEntry.new(
            name: pending.name,
            offset: offset,
            size_on_disk: size_on_disk,
            uncompressed_size: pending.compress ? pending.uncompressed_size : 0,
            archive_part: archive_part,
            flags: flags
          )
        end

        def write_footer(io, entries, num_parts)
          file_list_offset = io.pos

          # Build file entry binary data
          entry_data = entries.map { |e| serialize_entry(e) }.join
          compressed_entries = LZ4.block_encode(entry_data)

          # Write: num_files (4 bytes) + compressed entries
          io.write([entries.size].pack("V"))
          io.write(compressed_entries)

          file_list_size = 4 + compressed_entries.bytesize

          # Write header
          header = serialize_header(file_list_offset, file_list_size, num_parts)
          io.write(header)

          # Write header size + signature
          header_with_footer_size = HEADER_SIZE + 8
          io.write([header_with_footer_size].pack("V"))
          io.write(SIGNATURE)
        end

        def serialize_entry(entry)
          name_bytes = entry.name.b.ljust(NAME_SIZE, "\x00")[0, NAME_SIZE]
          # Use stored flags if available, otherwise compute from compressed?
          flags = entry.flags || (entry.compressed? ? COMPRESSION_FLAG_LZ4 : 0)
          crc = 0 # TODO: calculate CRC if needed

          name_bytes + [
            entry.offset,
            entry.size_on_disk,
            entry.uncompressed_size,
            entry.archive_part,
            flags,
            crc
          ].pack("V V V V V V")
        end

        def serialize_header(file_list_offset, file_list_size, num_parts)
          md5 = "\x00" * 16 # TODO: calculate MD5 if needed

          [
            VERSION,
            file_list_offset,
            file_list_size,
            num_parts,
            0, # flags
            0  # priority
          ].pack("V V V v C C") + md5
        end

        def compress(data)
          return data if data.empty?
          LZ4.block_encode(data)
        end

        def continuation_path(part)
          dir = File.dirname(@path)
          base = File.basename(@path, ".pak")
          File.join(dir, "#{base}_#{part}.pak")
        end
      end
    end
  end
end
