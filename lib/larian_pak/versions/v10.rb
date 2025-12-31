# frozen_string_literal: true

module LarianPak
  module Versions
    # Reader for PAK version 10 (DOS1 classic)
    #
    # V10 has signature at START of file:
    #   [LSPK signature - 4 bytes]
    #   [header - 20 bytes]
    #   [uncompressed file list]
    #   [file data at DataOffset]
    #
    # Header10 structure (20 bytes):
    #   UInt32    Version
    #   UInt32    DataOffset
    #   UInt32    FileListSize
    #   UInt16    NumParts
    #   Byte      Flags
    #   Byte      Priority
    #   UInt32    NumFiles
    #
    # FileEntry10 (280 bytes):
    #   Byte[256]  Name (null-terminated)
    #   UInt32     OffsetInFile
    #   UInt32     SizeOnDisk
    #   UInt32     UncompressedSize
    #   UInt32     ArchivePart
    #   UInt32     Flags
    #   UInt32     Crc
    #
    module V10
      HEADER_SIZE = 20
      FILE_ENTRY_SIZE = 280
      NAME_SIZE = 256
      SIGNATURE_SIZE = 4

      Header = Data.define(
        :version, :data_offset, :file_list_size,
        :num_parts, :flags, :priority, :num_files
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
        io.seek(SIGNATURE_SIZE) # skip "LSPK"
        data = io.read(HEADER_SIZE)

        values = data.unpack("V V V v C C V")
        Header.new(
          version: values[0],
          data_offset: values[1],
          file_list_size: values[2],
          num_parts: values[3],
          flags: values[4],
          priority: values[5],
          num_files: values[6]
        )
      end

      def self.read_file_entries(io, header)
        # File list starts right after header (uncompressed)
        io.seek(SIGNATURE_SIZE + HEADER_SIZE)

        entries = []
        header.num_files.times do
          entry_data = io.read(FILE_ENTRY_SIZE)

          name = entry_data[0, NAME_SIZE].unpack1("Z*")
          relative_offset, size_on_disk, uncompressed_size, archive_part, flags, _crc =
            entry_data[NAME_SIZE, 24].unpack("V V V V V V")

          # V10 offsets are relative to data_offset
          absolute_offset = header.data_offset + relative_offset

          entries << FileEntry.new(
            name: name,
            offset: absolute_offset,
            size_on_disk: size_on_disk,
            uncompressed_size: uncompressed_size,
            archive_part: archive_part,
            flags: flags
          )
        end

        entries
      end

      # Writer for V10 PAK files (DOS1 classic format)
      # V10 stores files uncompressed
      class Writer
        VERSION = 10
        SIGNATURE = "LSPK"

        PendingFile = Data.define(:name, :content)

        def initialize(path)
          @path = path
          @pending_files = []
        end

        def add_file(name, content)
          @pending_files << PendingFile.new(name: name, content: content.b)
        end

        def add_file_from_path(name, source_path)
          add_file(name, File.binread(source_path))
        end

        def save
          File.open(@path, "wb") do |io|
            # Calculate layout
            num_files = @pending_files.size
            file_list_size = num_files * FILE_ENTRY_SIZE
            data_offset = SIGNATURE_SIZE + HEADER_SIZE + file_list_size

            # Write signature
            io.write(SIGNATURE)

            # Write header
            io.write(serialize_header(data_offset, file_list_size, num_files))

            # Calculate file offsets (relative to data_offset)
            entries = []
            current_offset = 0
            @pending_files.each do |pending|
              entries << {
                name: pending.name,
                offset: current_offset,
                size: pending.content.bytesize
              }
              current_offset += pending.content.bytesize
            end

            # Write file entries
            entries.each do |entry|
              io.write(serialize_entry(entry))
            end

            # Write file data
            @pending_files.each do |pending|
              io.write(pending.content)
            end
          end
        end

        private

        def serialize_header(data_offset, file_list_size, num_files)
          [
            VERSION,
            data_offset,
            file_list_size,
            1,          # num_parts
            0,          # flags
            0,          # priority
            num_files
          ].pack("V V V v C C V")
        end

        def serialize_entry(entry)
          name_bytes = entry[:name].b.ljust(NAME_SIZE, "\x00")[0, NAME_SIZE]
          name_bytes + [
            entry[:offset],  # relative to data_offset
            entry[:size],    # size_on_disk
            0,               # uncompressed_size (0 = stored uncompressed)
            0,               # archive_part
            0,               # flags
            0                # crc
          ].pack("V V V V V V")
        end
      end
    end
  end
end
