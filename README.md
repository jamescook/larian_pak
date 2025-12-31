# larian_pak

A Ruby library for reading and writing PAK archive files used by Larian Studios games.

## Supported Games

- **Baldur's Gate 3** (PAK version 18)
- **Divinity: Original Sin 2** (PAK versions 13, 10)
- **Divinity: Original Sin 1 Enhanced Edition** (PAK version 13)
- **Divinity: Original Sin 1 Classic** (PAK version 10)

Legacy formats (v7, v9) from early DOS1 releases have partial read support but are untested.

## Installation

Add to your Gemfile:

```ruby
gem "larian_pak"
```

Or install directly:

```bash
gem install larian_pak
```

## Usage

### Reading PAK files

```ruby
require "larian_pak"

# Open a PAK file
package = LarianPak::Package.read("path/to/file.pak")

# List files
package.files.each do |entry|
  puts "#{entry.name} - #{entry.size_on_disk} bytes"
end

# Extract a specific file
content = package.extract("Public/Game/meta.lsx")
File.binwrite("meta.lsx", content)

# Extract all files
package.extract_all("output_directory/")
```

### Creating PAK files

```ruby
require "larian_pak"

# Create a V18 PAK (BG3 format)
writer = LarianPak::Versions::V18::Writer.new("output.pak")
writer.add_file("path/in/archive.txt", "file contents")
writer.add_file_from_path("another/file.lsx", "local/source.lsx")
writer.save

# Create a V13 PAK (DOS2 format)
writer = LarianPak::Versions::V13::Writer.new("output.pak")
writer.add_file("data.txt", content, compress: true)   # LZ4 compressed
writer.add_file("raw.bin", binary, compress: false)    # stored uncompressed
writer.save
```

### File entry properties

```ruby
entry = package.files.first

entry.name              # Full path within archive
entry.offset            # Byte offset in PAK file
entry.size_on_disk      # Compressed size (or raw size if uncompressed)
entry.uncompressed_size # Original size (0 if stored uncompressed)
entry.compressed?       # true if LZ4 compressed
entry.flags             # Raw flags byte (0x02 = LZ4)
entry.archive_part      # For multi-part archives
```

## Multi-part Archives

Large PAK files (like BG3's VirtualTextures.pak) may span multiple files. The library automatically handles reading from continuation files (`_1.pak`, `_2.pak`, etc.) when extracting.

Writing multi-part archives is not currently supported.

## Requirements

- Ruby 3.2+
- extlz4 gem (for LZ4 compression)

## License

MIT
