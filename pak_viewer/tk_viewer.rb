#!/usr/bin/env ruby

Process.setproctitle("pak-viewer")

# Tk PAK Viewer - exercises larian_pak with a Tk GUI
#
# Usage: ruby tk_viewer.rb
#
# Requires: Local tk gem from ~/open_source/tk

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../../tk/lib", __dir__)

require "tk"
require "larian_pak"

Tk.appname("PAK Viewer")

class PakViewer
  def initialize
    @root = TkRoot.new { title "PAK Viewer" }
    @root.minsize(800, 600)
    @package = nil
    @file_entries = {}  # tree item id -> FileEntry

    setup_ui
  end

  def setup_ui
    # Top frame with open button
    top_frame = TkFrame.new(@root)
    top_frame.pack(side: "top", fill: "x", padx: 10, pady: 10)

    @open_btn = TkButton.new(top_frame) do
      text "Open PAK File..."
    end
    @open_btn.command { open_file }
    @open_btn.pack(side: "left", padx: 5)

    @extract_btn = TkButton.new(top_frame) do
      text "Extract to..."
      state "disabled"
    end
    @extract_btn.command { extract_selected }
    @extract_btn.pack(side: "left", padx: 5)

    @status_label = TkLabel.new(top_frame) { text "" }
    @status_label.pack(side: "left", padx: 20)

    # Progress bar
    @progress_var = TkVariable.new(0)
    @progress = Tk::Tile::Progressbar.new(top_frame) do
      orient "horizontal"
      length 200
      mode "determinate"
    end
    @progress["variable"] = @progress_var
    @progress.pack(side: "right", padx: 10)

    # Path entry row (workaround for .app navigation on macOS)
    path_frame = TkFrame.new(@root)
    path_frame.pack(side: "top", fill: "x", padx: 10, pady: 5)

    TkLabel.new(path_frame) { text "Path:" }.pack(side: "left")

    @path_var = TkVariable.new(File.expand_path("samples", __dir__))
    @path_entry = TkEntry.new(path_frame) do
      width 60
    end
    @path_entry.textvariable = @path_var
    @path_entry.pack(side: "left", fill: "x", expand: true, padx: 5)
    @path_entry.bind("Return") { load_from_path }

    @load_btn = TkButton.new(path_frame) do
      text "Load"
    end
    @load_btn.command { load_from_path }
    @load_btn.pack(side: "left", padx: 5)

    # Main content - treeview with scrollbar
    content_frame = TkFrame.new(@root)
    content_frame.pack(side: "top", fill: "both", expand: true, padx: 10, pady: 5)

    # Scrollbars
    yscroll = TkScrollbar.new(content_frame)
    xscroll = TkScrollbar.new(content_frame) { orient "horizontal" }

    # Treeview for file listing
    @tree = Tk::Tile::Treeview.new(content_frame)
    @tree["columns"] = "files size compressed"

    @tree.headingconfigure("#0", text: "Name", anchor: "w")
    @tree.headingconfigure("files", text: "Files", anchor: "e")
    @tree.headingconfigure("size", text: "Size", anchor: "e")
    @tree.headingconfigure("compressed", text: "Compressed", anchor: "center")

    @tree.columnconfigure("#0", width: 400, anchor: "w")
    @tree.columnconfigure("files", width: 60, anchor: "e")
    @tree.columnconfigure("size", width: 120, anchor: "e")
    @tree.columnconfigure("compressed", width: 100, anchor: "center")

    # Connect scrollbars
    yscroll.command { |*args| @tree.yview(*args) }
    xscroll.command { |*args| @tree.xview(*args) }
    @tree.yscrollcommand { |*args| yscroll.set(*args) }
    @tree.xscrollcommand { |*args| xscroll.set(*args) }

    # Grid layout for scrollable treeview
    @tree.grid(row: 0, column: 0, sticky: "nsew")
    yscroll.grid(row: 0, column: 1, sticky: "ns")
    xscroll.grid(row: 1, column: 0, sticky: "ew")

    TkGrid.columnconfigure(content_frame, 0, weight: 1)
    TkGrid.rowconfigure(content_frame, 0, weight: 1)

    # Show/hide extract button based on selection (defer to let selection update first)
    @tree.bind("ButtonRelease-1") { Tk.after(10) { on_tree_select } }

    # Bottom status bar
    @bottom_status = TkLabel.new(@root) do
      text "Select a PAK file to view contents"
      anchor "w"
    end
    @bottom_status.pack(side: "bottom", fill: "x", padx: 10, pady: 5)
  end

  def open_file
    filetypes = [["PAK Files", [".pak"]], ["All Files", ["*"]]]
    initial_dir = @path_var.value

    path = Tk.getOpenFile(
      "filetypes" => filetypes,
      "initialdir" => initial_dir,
      "title" => "Select PAK File"
    )

    return if path.empty?

    # Update path entry to match selected file's directory
    @path_var.value = File.dirname(path)
    load_pak(path)
  end

  def load_from_path
    path = File.expand_path(@path_var.value.strip)
    return if path.empty?

    if File.file?(path) && path.end_with?(".pak")
      load_pak(path)
    elsif File.directory?(path)
      # Find first .pak file in directory
      pak_files = Dir.glob(File.join(path, "*.pak"))
      if pak_files.empty?
        @bottom_status.text = "No .pak files found in #{path}".dup
      elsif pak_files.size == 1
        load_pak(pak_files.first)
      else
        @bottom_status.text = "Multiple .pak files found (#{pak_files.size}) - select one".dup
        # Open file dialog at that path
        selected = Tk.getOpenFile(
          "filetypes" => [["PAK Files", [".pak"]], ["All Files", ["*"]]],
          "initialdir" => path,
          "title" => "Select PAK File"
        )
        load_pak(selected) unless selected.empty?
      end
    else
      @bottom_status.text = "Invalid path: #{path}".dup
    end
  end

  def set_controls_enabled(enabled)
    state = enabled ? "normal" : "disabled"
    @open_btn.state = state
    @load_btn.state = state
    @path_entry.state = state
    @extract_btn.state = enabled && @package && !@tree.selection.empty? ? "normal" : "disabled"
  end

  def reset_progress
    @progress_var.value = 0
    @progress.pack_forget
  end

  def show_progress
    @progress_var.value = 0
    @progress.pack(side: "right", padx: 10)
  end

  def load_pak(path)
    # Clear existing items
    @tree.children("").each { |child| @tree.delete(child) }
    @package = nil
    @file_entries = {}
    @pak_path = path

    @status_label.text = "Loading..."
    set_controls_enabled(false)
    show_progress

    # Shared state
    state = {
      current: 0,
      total: 0,
      done: false,
      error: nil,
      data: nil,
      start_time: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    }

    # Spawn worker subprocess
    worker_script = File.expand_path("parse_worker.rb", __dir__)
    cmd = ["ruby", worker_script, path]

    Thread.new do
      IO.popen(cmd, "r") do |io|
        io.each_line do |line|
          line = line.strip
          if line.start_with?("PROGRESS:")
            parts = line.sub("PROGRESS:", "").split("/")
            state[:current] = parts[0].to_i
            state[:total] = parts[1].to_i
          elsif line.start_with?("DATA:")
            state[:elapsed] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:start_time]
            state[:data] = line.sub("DATA:", "")
            state[:done] = true
          elsif line.start_with?("ERROR:")
            state[:elapsed] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:start_time]
            state[:error] = line.sub("ERROR:", "")
            state[:done] = true
          end
        end
      end
      state[:elapsed] ||= Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:start_time]
      state[:done] = true
    end

    # Poll progress
    poll_parse(state, path)
  end

  def poll_parse(state, path)
    if state[:done]
      if state[:error]
        @status_label.text = "Error"
        @bottom_status.text = "Error: #{state[:error]}".dup
        set_controls_enabled(true)
        reset_progress
      elsif state[:data]
        populate_tree(state[:data], path, state[:elapsed])
      end
    else
      # Update progress
      if state[:total] > 0
        progress = (state[:current] * 100) / state[:total]
        @progress_var.value = progress
        @bottom_status.text = "Parsing: #{state[:current]}/#{state[:total]} files...".dup
      end
      Tk.after(50) { poll_parse(state, path) }
    end
  end

  def populate_tree(json_data, path, elapsed)
    require "json"
    data = JSON.parse(json_data)

    # Load package for extraction (fast - just header)
    @package = LarianPak::Package.read(path)

    # Build file lookup by name
    file_lookup = {}
    @package.files.each { |e| file_lookup[e.name] = e }

    # Populate treeview
    total_size = 0
    compressed_count = 0

    data["tree"].each do |dir_data|
      dir_id = @tree.insert("", "end",
        "text" => dir_data["dir"].dup,
        "values" => [dir_data["file_count"].to_s, "", ""],
        "open" => false
      )

      dir_data["files"].each do |file|
        size_str = format_size(file["size"])
        compressed = file["compressed"] ? "Yes" : "No"
        total_size += file["size"]
        compressed_count += 1 if file["compressed"]

        item_id = @tree.insert(dir_id, "end",
          "text" => file["filename"].dup,
          "values" => ["", size_str, compressed]
        )
        @file_entries[item_id] = file_lookup[file["name"]]
      end
    end

    @progress_var.value = 100
    @status_label.text = "#{File.basename(path)} (V#{data["version"]})".dup
    @bottom_status.text = format(
      "%s - %d files, %s total (%d compressed) - %.2fs",
      File.basename(path),
      data["file_count"],
      format_size(total_size),
      compressed_count,
      elapsed
    ).dup
    set_controls_enabled(true)
    reset_progress
  end

  def format_size(bytes)
    return "0 B" if bytes == 0

    units = ["B", "KB", "MB", "GB"]
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = [exp, units.length - 1].min

    format("%.1f %s", bytes.to_f / (1024**exp), units[exp])
  end

  def on_tree_select
    selected = @tree.selection
    if selected.empty? || @package.nil?
      @extract_btn.state = "disabled"
    else
      @extract_btn.state = "normal"
    end
  end

  def extract_selected
    return unless @package

    selected = @tree.selection
    return if selected.empty?

    item = selected.first
    entry = @file_entries[item]

    if entry
      extract_file(entry)
    else
      extract_folder(item)
    end
  end

  def extract_file(entry)
    initial_name = File.basename(entry.name)
    save_path = Tk.getSaveFile(
      "initialfile" => initial_name,
      "title" => "Extract file to..."
    )

    return if save_path.empty?

    begin
      content = @package.extract(entry)
      File.binwrite(save_path, content)
      @bottom_status.text = "Extracted: #{entry.name} (#{format_size(content.bytesize)})".dup
    rescue => e
      @bottom_status.text = "Extract failed: #{e.message}".dup
    end
  end

  def extract_folder(folder_item)
    # Get all file entries under this folder
    entries = []
    @tree.children(folder_item).each do |child|
      entry = @file_entries[child]
      entries << entry if entry
    end

    if entries.empty?
      @bottom_status.text = "No files in folder".dup
      return
    end

    # Get destination directory
    dest_dir = Tk.chooseDirectory("title" => "Extract #{entries.size} files to...")
    return if dest_dir.empty?

    # Disable UI during extraction
    set_controls_enabled(false)
    show_progress

    # Get folder name from tree item
    folder_name = @tree.itemcget(folder_item, "text")

    # Shared state
    state = {
      extracted: 0,
      total: entries.size,
      total_bytes: 0,
      done: false,
      error: nil,
      start_time: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    }

    # Spawn worker subprocess
    worker_script = File.expand_path("extract_worker.rb", __dir__)
    cmd = ["ruby", worker_script, @package.path, folder_name, dest_dir]

    Thread.new do
      IO.popen(cmd, "r") do |io|
        io.each_line do |line|
          line = line.strip
          if line == "DONE"
            state[:done] = true
          elsif line.start_with?("ERROR:")
            state[:error] = line.sub("ERROR:", "")
            state[:done] = true
          elsif line =~ /^(\d+)\/(\d+)\/(\d+)$/
            state[:extracted] = $1.to_i
            state[:total] = $2.to_i
            state[:total_bytes] = $3.to_i
          end
        end
      end
      state[:done] = true unless state[:done]
      state[:elapsed] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - state[:start_time]
    end

    # Poll progress
    poll_worker(state)
  end

  def poll_worker(state)
    if state[:done]
      if state[:error]
        @bottom_status.text = "Extract failed: #{state[:error]}".dup
      else
        @progress_var.value = 100
        @bottom_status.text = format(
          "Extracted %d files (%s) in %.2fs",
          state[:total],
          format_size(state[:total_bytes]),
          state[:elapsed]
        ).dup
      end
      set_controls_enabled(true)
      Tk.after(200) { reset_progress }
    else
      # Update progress
      if state[:total] > 0
        progress = (state[:extracted] * 100) / state[:total]
        @progress_var.value = progress
        @bottom_status.text = "Extracting: #{state[:extracted]}/#{state[:total]} files...".dup
      end
      Tk.after(50) { poll_worker(state) }
    end
  end

  def run
    Tk.mainloop
  end
end

PakViewer.new.run
