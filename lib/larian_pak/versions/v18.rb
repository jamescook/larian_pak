# frozen_string_literal: true

require "extlz4"

module LarianPak
  module Versions
    # Reader for PAK version 18 (BG3 Release)
    #
    # Note: V15/V16 existed during BG3 Early Access (Oct 2020 - Aug 2023)
    # but are no longer in use. All current BG3 installs use V18.
    # We don't actively support V15/V16 - they technically share this
    # reader but will emit a warning if encountered.
    #
    # V15/V16/V18 have signature at START of file:
    #   [LSPK signature - 4 bytes]
    #   [header]
    #   [file data]
    #   [compressed file list]
    #
    # Header16 structure (36 bytes) - used by V16 and V18:
    #   UInt32    Version
    #   UInt64    FileListOffset
    #   UInt32    FileListSize (compressed)
    #   Byte      Flags
    #   Byte      Priority
    #   Byte[16]  MD5
    #   UInt16    NumParts
    #
    # FileEntry15 (296 bytes) - used by V15/V16:
    #   Byte[256]  Name
    #   UInt64     OffsetInFile
    #   UInt64     SizeOnDisk
    #   UInt64     UncompressedSize
    #   UInt32     ArchivePart
    #   UInt32     Flags
    #   UInt32     Crc
    #   UInt32     Unknown2
    #
    # FileEntry18 (272 bytes) - used by V18:
    #   Byte[256]  Name
    #   UInt32     OffsetInFile1 (lower 32 bits)
    #   UInt16     OffsetInFile2 (upper 16 bits)
    #   Byte       ArchivePart
    #   Byte       Flags
    #   UInt32     SizeOnDisk
    #   UInt32     UncompressedSize
    #
    module V18
      HEADER_SIZE = 36
      FILE_ENTRY_SIZE_V15 = 296
      FILE_ENTRY_SIZE_V18 = 272
      NAME_SIZE = 256
      SIGNATURE_SIZE = 4

      Header = Data.define(
        :version, :file_list_offset, :file_list_size,
        :flags, :priority, :md5, :num_parts
      )

      UNTESTED_VERSIONS = [15, 16].freeze

      def self.read(io, path, sig_location)
        header = read_header(io)

        if UNTESTED_VERSIONS.include?(header.version)
          warn "LarianPak: V#{header.version} support is untested (no real files available)"
        end

        files = read_file_entries(io, header)

        Package.new(
          version: header.version,
          files: files,
          path: path,
          flags: header.flags
        )
      end

      def self.read_header(io)
        io.seek(SIGNATURE_SIZE) # skip "LSPK"
        data = io.read(HEADER_SIZE)

        values = data.unpack("V Q< V C C a16 v")
        Header.new(
          version: values[0],
          file_list_offset: values[1],
          file_list_size: values[2],
          flags: values[3],
          priority: values[4],
          md5: values[5],
          num_parts: values[6]
        )
      end

      def self.read_file_entries(io, header)
        io.seek(header.file_list_offset)

        # V18 file list structure:
        #   4 bytes: num_files
        #   4 bytes: compressed_entries_size
        #   compressed entry data
        num_files = io.read(4).unpack1("V")
        compressed_size = io.read(4).unpack1("V")
        compressed_data = io.read(compressed_size)

        entry_size = header.version == 18 ? FILE_ENTRY_SIZE_V18 : FILE_ENTRY_SIZE_V15
        expected_size = num_files * entry_size
        decompressed = LZ4.block_decode(compressed_data, expected_size)

        entries = []
        num_files.times do |i|
          offset = i * entry_size
          entry_data = decompressed[offset, entry_size]

          if header.version == 18
            entries << parse_entry_v18(entry_data)
          else
            entries << parse_entry_v15(entry_data)
          end
        end

        entries
      end

      def self.parse_entry_v18(data)
        name = data[0, NAME_SIZE].unpack1("Z*")

        offset1, offset2, archive_part, flags, size_on_disk, uncompressed_size =
          data[NAME_SIZE, 16].unpack("V v C C V V")

        file_offset = offset1 | (offset2 << 32)

        FileEntry.new(
          name: name,
          offset: file_offset,
          size_on_disk: size_on_disk,
          uncompressed_size: uncompressed_size,
          archive_part: archive_part,
          flags: flags
        )
      end

      def self.parse_entry_v15(data)
        name = data[0, NAME_SIZE].unpack1("Z*")

        file_offset, size_on_disk, uncompressed_size, archive_part, flags, _crc, _unknown =
          data[NAME_SIZE, 40].unpack("Q< Q< Q< V V V V")

        FileEntry.new(
          name: name,
          offset: file_offset,
          size_on_disk: size_on_disk,
          uncompressed_size: uncompressed_size,
          archive_part: archive_part,
          flags: flags
        )
      end

      # Writer for V18 PAK files (BG3 format)
      class Writer
        VERSION = 18
        SIGNATURE = "LSPK"
        COMPRESSION_FLAG_LZ4 = 0x02

        PendingFile = Data.define(:name, :content, :uncompressed_size, :compress)

        def initialize(path)
          @path = path
          @pending_files = []
        end

        def add_file(name, content, compress: true)
          content = content.b
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
          File.open(@path, "wb") do |io|
            # Write signature
            io.write(SIGNATURE)

            # Write placeholder header (will update file_list_offset later)
            header_pos = io.pos
            io.write("\x00" * HEADER_SIZE)

            # Write file data
            entries = write_file_data(io)

            # Write file list
            file_list_offset = io.pos
            file_list_size = write_file_list(io, entries)

            # Go back and write real header
            io.seek(header_pos)
            io.write(serialize_header(file_list_offset, file_list_size))
          end
        end

        private

        def write_file_data(io)
          @pending_files.map do |pending|
            offset = io.pos
            if pending.compress
              data = compress(pending.content)
              flags = COMPRESSION_FLAG_LZ4
            else
              data = pending.content
              flags = 0
            end
            io.write(data)

            FileEntry.new(
              name: pending.name,
              offset: offset,
              size_on_disk: data.bytesize,
              uncompressed_size: pending.compress ? pending.uncompressed_size : 0,
              archive_part: 0,
              flags: flags
            )
          end
        end

        def write_file_list(io, entries)
          entry_data = entries.map { |e| serialize_entry(e) }.join
          compressed_entries = LZ4.block_encode(entry_data)

          # V18 file list: num_files (4) + compressed_size (4) + compressed_data
          io.write([entries.size].pack("V"))
          io.write([compressed_entries.bytesize].pack("V"))
          io.write(compressed_entries)

          8 + compressed_entries.bytesize
        end

        def serialize_entry(entry)
          name_bytes = entry.name.b.ljust(NAME_SIZE, "\x00")[0, NAME_SIZE]

          # Pack 48-bit offset into 32-bit + 16-bit
          offset1 = entry.offset & 0xFFFFFFFF
          offset2 = (entry.offset >> 32) & 0xFFFF

          # Use stored flags if available, otherwise compute from compressed?
          flags = entry.flags || (entry.compressed? ? COMPRESSION_FLAG_LZ4 : 0)

          name_bytes + [
            offset1,
            offset2,
            entry.archive_part,
            flags,
            entry.size_on_disk,
            entry.uncompressed_size
          ].pack("V v C C V V")
        end

        def serialize_header(file_list_offset, file_list_size)
          md5 = "\x00" * 16

          [
            VERSION,
            file_list_offset,
            file_list_size,
            0, # flags
            0, # priority
          ].pack("V Q< V C C") + md5 + [1].pack("v") # num_parts = 1
        end

        def compress(data)
          return data if data.empty?
          LZ4.block_encode(data)
        end
      end
    end
  end
end
