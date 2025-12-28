class Stepped::Achievement < ActiveRecord::Base
  class << self
    def exists_for?(action)
      return false if action.checksum.nil?

      exists? action.attributes.slice("checksum_key", "checksum")
    end

    def raise_if_exists_for?(action)
      if exists_for?(action)
        raise ExistsError
      end
    end

    def grand_to(action)
      create! action.attributes.slice("checksum_key", "checksum")
    end

    def erase_of(action)
      where(action.attributes.slice("checksum_key")).destroy_all
    end
  end

  class ExistsError < StandardError; end
end
