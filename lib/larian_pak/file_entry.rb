# frozen_string_literal: true

module LarianPak
  class FileEntry
    # Compression flags (from lslib)
    FLAG_LZ4 = 0x02

    attr_reader :name, :offset, :size_on_disk, :uncompressed_size, :archive_part, :flags

    def initialize(name:, offset:, size_on_disk:, uncompressed_size:, archive_part: 0, flags: nil)
      @name = name
      @offset = offset
      @size_on_disk = size_on_disk
      @uncompressed_size = uncompressed_size
      @archive_part = archive_part
      @flags = flags
    end

    def compressed?
      if @flags
        (@flags & FLAG_LZ4) != 0
      else
        # Fallback for older formats without flags
        uncompressed_size > 0 && size_on_disk != uncompressed_size
      end
    end

    def to_h
      {
        name: name,
        offset: offset,
        size_on_disk: size_on_disk,
        uncompressed_size: uncompressed_size,
        archive_part: archive_part,
        compressed: compressed?
      }
    end
  end
end
