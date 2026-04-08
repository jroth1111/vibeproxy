#!/usr/bin/env ruby

require "json"
require "net/http"
require "optparse"
require "set"
require "uri"
require "yaml"

options = {
  provider: "ollama-pro",
  display_name: "Ollama Pro",
  base_url: "https://ollama.com/v1",
  tags_url: "https://ollama.com/api/tags",
  config_path: File.expand_path("~/.cli-proxy-api/config.yaml"),
}

OptionParser.new do |parser|
  parser.banner = "Usage: sync-ollama-cloud-provider.rb --api-key KEY [options]"

  parser.on("--api-key KEY", "Ollama Cloud bearer token") { |value| options[:api_key] = value }
  parser.on("--provider NAME", "Provider id to write into openai-compatibility") { |value| options[:provider] = value }
  parser.on("--display-name NAME", "Display name for the provider entry") { |value| options[:display_name] = value }
  parser.on("--base-url URL", "OpenAI-compatible base URL used by VibeProxy") { |value| options[:base_url] = value }
  parser.on("--tags-url URL", "Ollama tags endpoint used to discover models") { |value| options[:tags_url] = value }
  parser.on("--config-path PATH", "Config file to rewrite") { |value| options[:config_path] = File.expand_path(value) }
end.parse!

if options[:api_key].to_s.empty?
  abort("missing required --api-key")
end

def fetch_tags(tags_url, api_key)
  uri = URI(tags_url)
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = "Bearer #{api_key}"
  request["Accept"] = "application/json"

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      abort("failed to fetch #{tags_url}: HTTP #{response.code} #{response.message}\n#{response.body}")
    end
    JSON.parse(response.body)
  end
end

def sanitize_alias(model_name)
  model_name
    .downcase
    .gsub(/[^a-z0-9.\-]+/, "-")
    .gsub(/-+/, "-")
    .gsub(/\A-|-+\z/, "")
end

payload = fetch_tags(options[:tags_url], options[:api_key])
models = Array(payload["models"]).map { |entry| entry["model"].to_s.strip }.reject(&:empty?)

if models.empty?
  abort("no models returned by #{options[:tags_url]}")
end

used_aliases = Set.new
model_entries = models.map do |model_name|
  base_alias = "#{sanitize_alias(model_name)}-#{options[:provider]}"
  alias_name = base_alias
  suffix = 2
  while used_aliases.include?(alias_name)
    alias_name = "#{base_alias}-#{suffix}"
    suffix += 1
  end
  used_aliases << alias_name

  {
    "alias" => alias_name,
    "name" => model_name,
    "register-canonical-name" => false,
  }
end

provider_entry = {
  "name" => options[:provider],
  "display-name" => options[:display_name],
  "help-text" => "Imported from Ollama Cloud /api/tags. Models stay alias-only to avoid colliding with existing raw route names.",
  "base-url" => options[:base_url],
  "api-key-entries" => [
    { "api-key" => options[:api_key] },
  ],
  "models" => model_entries,
}

config_root =
  if File.exist?(options[:config_path])
    YAML.load_file(options[:config_path]) || {}
  else
    {}
  end

openai_compatibility = Array(config_root["openai-compatibility"])
openai_compatibility.reject! do |entry|
  entry.is_a?(Hash) && entry["name"].to_s == options[:provider]
end
openai_compatibility << provider_entry
config_root["openai-compatibility"] = openai_compatibility

File.write(options[:config_path], YAML.dump(config_root))

puts "synced provider #{options[:provider]} into #{options[:config_path]}"
puts "base-url: #{options[:base_url]}"
puts "models (#{model_entries.length}):"
model_entries.each do |entry|
  puts "  #{entry['alias']} => #{entry['name']}"
end
