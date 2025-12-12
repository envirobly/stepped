# frozen_string_literal: true

module Stepped
  class Sample < ActiveRecord::Base
    self.table_name = "stepped_samples"

    def greeting
      "Hello, #{name}"
    end
  end
end
