# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module ScrumManager
  class FizzyClient
    class ConfigurationError < StandardError; end
    class RequestError < StandardError; end

    BASE_URL = "https://app.fizzy.do"
    PER_PAGE = 100

    def initialize(token:, account_slug:)
      @token = token.to_s.strip
      @account_slug = account_slug.to_s.strip.sub(%r{\A/+}, "")

      raise ConfigurationError, "Set FIZZY_TOKEN in your environment." if @token.empty?
      raise ConfigurationError, "Set FIZZY_ACCOUNT_SLUG in your environment." if @account_slug.empty?
    end

    def sprint_tags
      all_tags
        .select { |tag| tag.fetch("title", "").downcase.start_with?("sprint") }
        .sort_by { |tag| tag["created_at"].to_s }
        .reverse
    end

    def cards_for_sprint(tag_title)
      tag = sprint_tags.find { |candidate| candidate.fetch("title", "").casecmp?(tag_title) }
      raise RequestError, "Sprint tag not found: #{tag_title}" unless tag

      cards = paginated_json(cards_path, tag_ids: [tag.fetch("id")])
      cards.map { |card| card_detail(card) }
    end

    private

    def all_tags
      paginated_json(tags_path)
    end

    def card_detail(card)
      number = card["number"]
      return card unless number

      get_json(card_path(number))
    rescue RequestError
      card
    end

    def paginated_json(path, params = {})
      page = 1
      results = []

      loop do
        payload = get_json(path, params.merge(page: page, per_page: PER_PAGE))
        page_items = Array(payload)
        results.concat(page_items)
        break if page_items.length < PER_PAGE

        page += 1
      end

      results
    end

    def get_json(path, params = {})
      uri = build_uri(path, params)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{@token}"
        request["Accept"] = "application/json"
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise RequestError, "GET #{uri.path} failed with #{response.code}: #{response.body}"
      end

      JSON.parse(response.body)
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
  end
end
