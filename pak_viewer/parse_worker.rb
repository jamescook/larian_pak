#!/usr/bin/env ruby
# Worker script for parsing PAK files - called as subprocess
# Usage: ruby parse_worker.rb <pak_path>
# Outputs progress: "PROGRESS:current/total"
# Outputs result: "DATA:<json>"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "larian_pak"
require "json"

$stdout.sync = true

pak_path = ARGV[0]
abort "Usage: parse_worker.rb <pak_path>" unless pak_path

begin
  package = LarianPak::Package.read(pak_path)

  total = package.files.size
  last_progress = 0

  # Group files by directory with progress
  dirs = Hash.new { |h, k| h[k] = [] }
  package.files.each_with_index do |entry, idx|
    dir = File.dirname(entry.name)
    dir = "(root)" if dir == "."
    # Use size_on_disk if uncompressed_size is 0 (e.g., VirtualTextures)
    size = entry.uncompressed_size > 0 ? entry.uncompressed_size : entry.size_on_disk
    dirs[dir] << {
      name: entry.name,
      filename: File.basename(entry.name),
      size: size,
      compressed: entry.compressed?
    }

    # Report progress every 5%
    progress = ((idx + 1) * 100) / total
    if progress >= last_progress + 5 || idx == total - 1
      last_progress = progress
      puts "PROGRESS:#{idx + 1}/#{total}"
    end
  end

  # Build tree structure
  tree = dirs.keys.sort.map do |dir|
    files = dirs[dir].sort_by { |f| f[:name] }
    {
      dir: dir,
      file_count: files.size,
      files: files
    }
  end

  result = {
    version: package.version,
    file_count: package.file_count,
    path: package.path,
    tree: tree
  }

  puts "DATA:#{JSON.generate(result)}"

rescue => e
  puts "ERROR:#{e.message}"
  exit 1
end
