# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

desc "Run e2e tests against sample PAK files"
task :e2e do
  require_relative "lib/larian_pak"

  samples_path = File.expand_path("samples", __dir__)

  unless File.directory?(samples_path)
    puts "Samples directory not found at: #{samples_path}"
    puts "Copy sample PAK files from your games into samples/ subdirectories"
    exit 1
  end

  pak_files = Dir.glob(File.join(samples_path, "**/*.pak"))
  if pak_files.empty?
    puts "No PAK files found in samples/"
    exit 1
  end

  puts "Found #{pak_files.count} sample PAK files"

  pak_files.each do |pak_path|
    puts "\n#{"=" * 60}"
    puts "Testing: #{pak_path.sub(samples_path + "/", "")}"
    puts "Size: #{File.size(pak_path)} bytes"
    puts "=" * 60

    begin
      package = LarianPak::Package.read(pak_path)
      puts "Version: #{package.version}"
      puts "Files: #{package.files.count}"

      puts "\nFirst 5 files:"
      package.files.first(5).each do |entry|
        status = entry.compressed? ? "compressed" : "stored"
        puts "  #{entry.name} (#{entry.uncompressed_size} bytes, #{status})"
      end

      # Test extraction of first file
      if package.files.any?
        first = package.files.first
        content = package.extract(first)
        puts "\nExtracted #{first.name}: #{content.bytesize} bytes"
      end

      puts "\nSUCCESS"
    rescue => e
      puts "ERROR: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end
end

task default: :test
