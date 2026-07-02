# frozen_string_literal: true

module ScrumManager
  class MemoryCache
    def initialize(default_ttl:)
      @default_ttl = default_ttl
      @store = {}
      @mutex = Mutex.new
    end

    def fetch(key, ttl: @default_ttl)
      cache_key = Array(key).join(":")
      now = Time.now

      @mutex.synchronize do
        entry = @store[cache_key]
        return entry[:value] if entry && entry[:expires_at] > now
      end

      value = yield

      @mutex.synchronize do
        @store[cache_key] = { value: value, expires_at: now + ttl }
      end

      value
    end

    def clear
      @mutex.synchronize { @store.clear }
    end
  end
end
