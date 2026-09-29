# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module ScrumManager
  class FizzyClient
    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    BASE_URL = "https://app.fizzy.do"

    def initialize(token:, account_slug:)
      @token = token.to_s.strip
      @account_slug = account_slug.to_s.strip.sub(%r{\A/+}, "")
      @log_http = truthy?(ENV["FIZZY_LOG_HTTP"])
      @log_response_body = ENV.fetch("FIZZY_LOG_RESPONSE_BODY", "true") != "false"
      @log_body_limit = Integer(ENV.fetch("FIZZY_LOG_BODY_LIMIT", "12000"))

      raise ConfigurationError, "Set FIZZY_TOKEN in your environment." if @token.empty?
      raise ConfigurationError, "Set FIZZY_ACCOUNT_SLUG in your environment." if @account_slug.empty?
    end

    def sprint_tags
      tags
        .select { |tag| tag.fetch("title", "").downcase.start_with?("sprint") }
        .sort_by { |tag| tag["created_at"].to_s }
        .reverse
    end

    def tags
      paginated_json(tags_path)
    end

    def cards_for_sprint(tag_title)
      tag = sprint_tags.find { |candidate| candidate.fetch("title", "").casecmp?(tag_title) }
      raise RequestError, "Sprint tag not found: #{tag_title}" unless tag

      cards_for_sprint_tag(tag)
    end

    def cards_for_sprint_tag(tag)
      cards = paginated_json(cards_path, tag_ids: [tag.fetch("id")])
      cards.map { |card| card_detail(card) }
    end

    def update_card(card_id, attributes)
      uri = build_uri(card_path(card_id), {})
      request_headers = {
        "Authorization" => "Bearer [REDACTED]",
        "Content-Type" => "application/json"
      }
      log_request("PATCH", uri, request_headers)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Patch.new(uri)
        request["Authorization"] = "Bearer #{@token}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(attributes)
        http.request(request)
      end
      log_response(response)

      response.is_a?(Net::HTTPSuccess)
    rescue SocketError, SystemCallError, Timeout::Error => e
      raise RequestError, "Could not reach Fizzy: #{e.message}"
    end

    private

    def card_detail(card)
      number = card["number"]
      return card unless number

      get_json(card_path(number))
    rescue RequestError
      card
    end

    def paginated_json(path, params = {})
      next_uri = build_uri(path, params)
      results = []

      while next_uri
        payload, response = get_json_response(next_uri)
        page_items = Array(payload)
        results.concat(page_items)

        next_uri = next_link_uri(response)
      end

      results
    end

    def get_json(path, params = {})
      get_json_response(build_uri(path, params)).first
    end

    def get_json_response(uri)
      request_headers = {
        "Authorization" => "Bearer [REDACTED]",
        "Accept" => "application/json"
      }
      log_request("GET", uri, request_headers)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@token}"
        request["Accept"] = "application/json"
        http.request(request)
      end
      log_response(response)

      unless response.is_a?(Net::HTTPSuccess)
        raise RequestError, "GET #{uri.path} failed with #{response.code}: #{response.body}"
      end

      [JSON.parse(response.body), response]
    rescue JSON::ParserError => e
      raise RequestError, "Fizzy returned invalid JSON: #{e.message}"
    rescue SocketError, SystemCallError, Timeout::Error => e
      raise RequestError, "Could not reach Fizzy: #{e.message}"
    end

    def build_uri(path, params)
      uri = URI.join(BASE_URL, path)
      uri.query = URI.encode_www_form(flatten_params(params)) unless params.empty?
      uri
    end

    def flatten_params(params)
      params.flat_map do |key, value|
        if value.is_a?(Array)
          value.map { |item| ["#{key}[]", item] }
        else
          [[key.to_s, value]]
        end
      end
    end

    def tags_path
      "/#{@account_slug}/tags"
    end

    def cards_path
      "/#{@account_slug}/cards"
    end

    def card_path(number)
      "/#{@account_slug}/cards/#{number}"
    end

    def next_link_uri(response)
      link_header = response["Link"].to_s
      return nil if link_header.empty?

      link_header.split(",").each do |link|
        match = link.match(/<([^>]+)>/)
        rel_match = link.match(/rel="([^"]+)"/)
        next unless match && rel_match
        next unless rel_match[1].split.include?("next")

        return URI.join(BASE_URL, match[1])
      end

      nil
    end

    def truthy?(value)
      %w[1 true yes on].include?(value.to_s.downcase)
    end

    def log_request(method, uri, headers)
      return unless @log_http

      warn "[Fizzy] request #{method} #{uri}"
      headers.each { |key, value| warn "[Fizzy] request header #{key}: #{value}" }
    end

    def log_response(response)
      return unless @log_http

      warn "[Fizzy] response status #{response.code} #{response.message}"
      response.each_header do |key, value|
        warn "[Fizzy] response header #{key}: #{value}"
      end
      return unless @log_response_body

      body = response.body.to_s
      if body.length > @log_body_limit
        warn "[Fizzy] response body #{body.byteslice(0, @log_body_limit)}... [truncated #{body.length - @log_body_limit} bytes]"
      else
        warn "[Fizzy] response body #{body}"
      end
    end
  end
end
