require 'cgi'
require 'uri'
require 'httparty'
require 'hashie'

libdir = File.dirname(__FILE__)
$LOAD_PATH.unshift(libdir) unless $LOAD_PATH.include?(libdir)

require 'createsend/version'
require 'createsend/client'
require 'createsend/campaign'
require 'createsend/list'
require 'createsend/segment'
require 'createsend/subscriber'
require 'createsend/template'
require 'createsend/person'
require 'createsend/administrator'

module CreateSend

  # Just allows callers to do CreateSend.oauth '...', '...' rather than
  # CreateSend::CreateSend.oauth '...', '...'
  class << self
    def oauth(access_token=nil, refresh_token=nil)
      r = CreateSend.oauth access_token, refresh_token
    end

    def refresh_token(refresh_token=nil)
      CreateSend.refresh_token refresh_token
    end

    def api_key(api_key=nil)
      r = CreateSend.api_key api_key
    end

    def base_uri(uri)
      r = CreateSend.base_uri uri
    end

    def base_oauth_uri(uri)
      r = CreateSend.base_oauth_uri uri
    end
  end

  # Represents a CreateSend API error. Contains specific data about the error.
  class CreateSendError < StandardError
    attr_reader :data
    def initialize(data)
      @data = data
      # @data should contain Code, Message and optionally ResultData
      extra = @data.ResultData ? "\nExtra result data: #{@data.ResultData}" : ""
      super "The CreateSend API responded with the following error"\
        " - #{@data.Code}: #{@data.Message}#{extra}"
    end
  end

  # Raised for HTTP response codes of 400...500
  class ClientError < StandardError; end
  # Raised for HTTP response codes of 500...600
  class ServerError < StandardError; end
  # Raised for HTTP response code of 400
  class BadRequest < CreateSendError; end
  # Raised for HTTP response code of 401
  class Unauthorized < CreateSendError; end
  # Raised for HTTP response code of 404
  class NotFound < ClientError; end

  # Raised for HTTP response code of 401, specifically when an OAuth token
  # has expired (Code: 121, Message: 'Expired OAuth Token')
  class ExpiredOAuthToken < Unauthorized; end

  # Provides high level CreateSend functionality/data you'll probably need.
  class CreateSend
    include HTTParty

    # Deals with an unfortunate situation where responses aren't valid json.
    class Parser::DealWithCreateSendInvalidJson < HTTParty::Parser
      # The createsend API returns an ID as a string when a 201 Created
      # response is returned. Unfortunately this is invalid json.
      def parse
        begin
          super
        rescue MultiJson::DecodeError => e
          body[1..-2] # Strip surrounding quotes and return as is.
        end
      end
    end
    parser Parser::DealWithCreateSendInvalidJson
    @@base_uri = "https://api.createsend.com/api/v3"
    @@base_oauth_uri = "https://api.createsend.com"
    @@api_key = ''
    headers({
      'User-Agent' => "createsend-ruby-#{VERSION}",
      'Content-Type' => 'application/json; charset=utf-8',
      'Accept-Encoding' => 'gzip, deflate' })
    base_uri @@base_uri

    # Resets authentication. Used before setting either CreateSend::CreateSend.access_token
    # or CreateSend::CreateSend.api_key.
    def self.reset_auth
      @@access_token = nil
      @@refresh_token = nil
      @@api_key = nil
      default_options[:basic_auth] = nil
    end

    # Gets/sets the base OAuth URI.
    def self.base_oauth_uri(uri=nil)
      return @@base_oauth_uri unless uri
      @@base_oauth_uri = uri
    end

    # Authenticate using an OAuth token (and refresh token)
    def self.oauth(access_token=nil, refresh_token=nil)
      return @@access_token, @@refresh_token unless access_token
      CreateSend.reset_auth
      @@access_token = access_token
      @@refresh_token = refresh_token if refresh_token
      headers({"Authorization" => "Bearer #{@@access_token}"})
    end

    # Refresh an OAuth token using a refresh token.
    def self.refresh_token(refresh_token=nil)

      # TODO: Refresh the token!

      ["new access token", "new refresh token"]
    end

    # Authenticate using an API key.
    def self.api_key(api_key=nil)
      return @@api_key unless api_key
      CreateSend.reset_auth
      @@api_key = api_key
      basic_auth @@api_key, 'x'
    end

    # Gets your CreateSend API key, given your site url, username and password.
    def apikey(site_url, username, password)
      site_url = CGI.escape(site_url)
      self.class.basic_auth username, password
      response = CreateSend.get("/apikey.json?SiteUrl=#{site_url}")
      self.class.default_options[:basic_auth] = nil
      # If an api key was being used, revert basic_auth to use @@api_key
      self.class.basic_auth(@@api_key, 'x') if @@api_key
      Hashie::Mash.new(response)
    end

    # Gets your clients.
    def clients
      response = CreateSend.get('/clients.json')
      response.map{|item| Hashie::Mash.new(item)}
    end

    # Get your billing details.
    def billing_details
      response = CreateSend.get('/billingdetails.json')
      Hashie::Mash.new(response)
    end

    # Gets valid countries.
    def countries
      response = CreateSend.get('/countries.json')
      response.parsed_response
    end

    # Gets the current date in your account's timezone.
    def systemdate
      response = CreateSend.get('/systemdate.json')
      Hashie::Mash.new(response)
    end

    # Gets valid timezones.
    def timezones
      response = CreateSend.get('/timezones.json')
      response.parsed_response
    end

    # Gets the administrators
    def administrators
      response = CreateSend.get('/admins.json')
      response.map{|item| Hashie::Mash.new(item)}
    end

    def get_primary_contact
      response = CreateSend.get('/primarycontact.json')
      Hashie::Mash.new(response)
    end

    def set_primary_contact(email)
      options = { :query => { :email => email } }
      response = CreateSend.put("/primarycontact.json", options)
      Hashie::Mash.new(response)
    end

    def self.get(*args); handle_response super end
    def self.post(*args); handle_response super end
    def self.put(*args); handle_response super end
    def self.delete(*args); handle_response super end

    def self.handle_response(response) # :nodoc:
      case response.code
      when 400
        raise BadRequest.new(Hashie::Mash.new response)
      when 401
        data = Hashie::Mash.new(response)
        if data.Code == 121
          raise ExpiredOAuthToken.new(data)
        end
        raise Unauthorized.new(data)
      when 404
        raise NotFound.new
      when 400...500
        raise ClientError.new
      when 500...600
        raise ServerError.new
      else
        response
      end
    end
  end
end