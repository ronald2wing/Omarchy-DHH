# DHH::Fxtwitter: the api.fxtwitter.com endpoints the helpers and tools read.

require 'uri'

module DHH
  module Fxtwitter
    BASE_URI = URI('https://api.fxtwitter.com').freeze
    # Every endpoint answers JSON.
    ACCEPT = 'application/json'

    module_function

    # DHH's profile: { user: { statuses: <post count>, ... } }.
    def profile_path
      "/2/profile/#{DHH::HANDLE}"
    end

    # One page of DHH's statuses, newest first; `cursor` names an older page.
    def statuses_path(count, cursor = nil)
      path = "/2/profile/#{DHH::HANDLE}/statuses?count=#{count}"
      path += "&cursor=#{URI.encode_www_form_component(cursor)}" unless cursor.nil?
      path
    end

    # One status by id: { code, message, tweet: { ... } }.
    def status_path(id)
      "/#{DHH::HANDLE}/status/#{URI.encode_www_form_component(id)}"
    end
  end
end
