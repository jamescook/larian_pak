# frozen_string_literal: true

module LarianPak
  module Versions
    # Reader for PAK versions 7 and 9
    #
    # Note: V7/V9 were used in early DOS1 releases (pre-2015) but Larian
    # has since updated Steam releases to newer formats. Current DOS1
    # Classic uses V10, DOS1:EE uses V13. V7/V9 files are essentially
    # unavailable now - we don't actively support them.
    #
    # Header structure (21 bytes):
    #   UInt32  Version
    #   UInt32  DataOffset
    #   UInt32  NumParts
    #   UInt32  FileListSize
    #   Byte    LittleEndian
    #   UInt32  NumFiles
    #
    # File entry structure (272 bytes):
    #   Byte[256]  Name (null-terminated)
    #   UInt32     OffsetInFile
    #   UInt32     SizeOnDisk
    #   UInt32     UncompressedSize
    #   UInt32     ArchivePart
    #
    module V9
      HEADER_SIZE = 21
      FILE_ENTRY_SIZE = 272
      NAME_SIZE = 256

      Header = Data.define(:version, :data_offset, :num_parts, :file_list_size, :little_endian, :num_files)

      def self.read(io, path, sig_location = nil)
        warn "LarianPak: V7/V9 support is untested - these are legacy formats from pre-2015 DOS1 releases"

        header = read_header(io)
        files = read_file_entries(io, header)

        Package.new(
          version: header.version,
          files: files,
          path: path
        )
      end

      def self.read_header(io)
        data = io.read(HEADER_SIZE)
        raise Error, "Truncated header" if data.nil? || data.bytesize < HEADER_SIZE

        values = data.unpack("V V V V C V")
        Header.new(
          version: values[0],
          data_offset: values[1],
          num_parts: values[2],
          file_list_size: values[3],
          little_endian: values[4],
          num_files: values[5]
        )
      end

      def self.read_file_entries(io, header)
        entries = []

        header.num_files.times do
          data = io.read(FILE_ENTRY_SIZE)
          raise Error, "Truncated file entry" if data.nil? || data.bytesize < FILE_ENTRY_SIZE

          name_bytes = data[0, NAME_SIZE]
          name = name_bytes.unpack1("Z*")

          offset, size_on_disk, uncompressed_size, archive_part = data[NAME_SIZE, 16].unpack("V V V V")

          entries << FileEntry.new(
            name: name,
            offset: offset,
            size_on_disk: size_on_disk,
            uncompressed_size: uncompressed_size,
            archive_part: archive_part
          )
        end

        entries
      end
    end
  end
end
