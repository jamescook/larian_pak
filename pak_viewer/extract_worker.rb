#!/usr/bin/env ruby
# Worker script for extraction - called as subprocess
# Usage: ruby extract_worker.rb <pak_path> <folder_prefix> <dest_dir>
# Outputs progress to stdout: "extracted/total bytes"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "larian_pak"

$stdout.sync = true

pak_path, folder_prefix, dest_dir = ARGV
abort "Usage: extract_worker.rb <pak_path> <folder_prefix> <dest_dir>" unless pak_path && folder_prefix && dest_dir

begin
  package = LarianPak::Package.read(pak_path)

  # Find matching entries
  entries = package.files.select { |f| File.dirname(f.name) == folder_prefix || File.dirname(f.name).start_with?("#{folder_prefix}/") }
  entries = entries.select { |f| File.dirname(f.name) == folder_prefix } if entries.empty?

  # Actually just match the folder name at end of path
  entries = package.files.select { |f| File.dirname(f.name).end_with?(folder_prefix) || File.dirname(f.name) == folder_prefix }

  total = entries.size
  abort "ERROR:No files found for #{folder_prefix}" if total == 0

  total_bytes = 0
  entries.each_with_index do |entry, idx|
    content = package.extract(entry)
    filename = File.basename(entry.name)
    File.binwrite(File.join(dest_dir, filename), content)
    total_bytes += content.bytesize

    puts "#{idx + 1}/#{total}/#{total_bytes}"
  end

  puts "DONE"
rescue => e
  puts "ERROR:#{e.message}"
  exit 1
end
