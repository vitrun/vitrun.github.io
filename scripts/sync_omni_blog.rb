#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "fileutils"
require "pathname"
require "yaml"

ROOT = Pathname.new(Dir.pwd)
SOURCE = Pathname.new(ARGV[0] || "../omni/blog").expand_path(ROOT)
POSTS_DIR = ROOT.join("_posts")

unless SOURCE.directory?
  warn "Source blog directory not found: #{SOURCE}"
  exit 1
end

def split_front_matter(text, file)
  match = text.match(/\A---\s*\n(.*?)\n---\s*\n?/m)
  unless match
    warn "Missing front matter: #{file}"
    exit 1
  end

  [match[1], text[match[0].length..] || ""]
end

def post_url(relative_path)
  category = relative_path.dirname.to_s
  basename = relative_path.basename(".md").to_s
  match = basename.match(/\A(\d{4})-(\d{2})-(\d{2})-(.+)\z/)
  unless match
    warn "Unexpected post filename: #{relative_path}"
    exit 1
  end

  "/#{category}/#{match[1]}/#{match[2]}/#{match[3]}/#{match[4]}.html"
end

post_files = SOURCE.children.select(&:directory?).flat_map do |category_dir|
  next [] if category_dir.basename.to_s == "attrs"

  category_dir.children.select { |path| path.file? && path.extname == ".md" }
end.sort

url_by_source = post_files.each_with_object({}) do |file, urls|
  rel = file.relative_path_from(SOURCE)
  urls[rel.to_s] = post_url(rel)
end

def rewrite_markdown_links(body, source_file, url_by_source)
  body.gsub(/\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) do |match|
    target = Regexp.last_match(1)
    rewritten =
      if target.start_with?("../attrs/img/")
        "/img/#{target.delete_prefix("../attrs/img/")}"
      elsif target.start_with?("../attrs/pdf/")
        "/pdf/#{target.delete_prefix("../attrs/pdf/")}"
      elsif target.match?(/\.md(?:#.+)?\z/) && !target.match?(/\A[a-z][a-z0-9+.-]*:/i)
        path_part, anchor = target.split("#", 2)
        resolved = source_file.dirname.join(path_part).cleanpath.relative_path_from(SOURCE).to_s
        if url_by_source.key?(resolved)
          "#{url_by_source.fetch(resolved)}#{anchor ? "##{anchor}" : ""}"
        else
          target
        end
      else
        target
      end

    match.sub(target, rewritten)
  end
end

def strip_duplicate_title(body, title)
  escaped = Regexp.escape(title.to_s.strip)
  body.sub(/\A\s*#\s+#{escaped}\s*\n+/, "")
end

FileUtils.rm_rf(POSTS_DIR)
FileUtils.mkdir_p(POSTS_DIR)

post_files.each do |source_file|
  relative = source_file.relative_path_from(SOURCE)
  category = relative.dirname.to_s
  front_matter, body = split_front_matter(source_file.read, source_file)
  data = YAML.safe_load(
    front_matter,
    permitted_classes: [Date, Time],
    aliases: true
  ) || {}

  data["layout"] = "post"
  data["categories"] = [category]
  data["permalink"] = url_by_source.fetch(relative.to_s)

  body = strip_duplicate_title(body, data["title"])
  body = rewrite_markdown_links(body, source_file, url_by_source)

  target = POSTS_DIR.join(relative)
  FileUtils.mkdir_p(target.dirname)
  target.write("#{data.to_yaml}---\n\n#{body}")
end

if SOURCE.join("attrs", "img").directory?
  FileUtils.mkdir_p(ROOT.join("img"))
  FileUtils.cp_r(Dir[SOURCE.join("attrs", "img", "*").to_s], ROOT.join("img"))
end

if SOURCE.join("attrs", "pdf").directory?
  FileUtils.mkdir_p(ROOT.join("pdf"))
  FileUtils.cp_r(Dir[SOURCE.join("attrs", "pdf", "*").to_s], ROOT.join("pdf"))
end

puts "Synced #{post_files.length} posts from #{SOURCE}"
