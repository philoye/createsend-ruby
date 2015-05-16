module CreateSend
  module Transactional
    class BasicEmail < CreateSend
      attr_accessor :options

      def self.groups(auth, options = {})
        cs = CreateSend.new auth
        response = cs.get "/transactional/basicemail/groups", :query => options
        response.map{|item| Hashie::Mash.new(item)}
      end

      def initialize(auth, client_id = nil)
        @auth = auth
        @client_id = client_id
        super
      end

      def send(options)
        query = {:client_id => @client_id} if @client_id
        response = post "/transactional/basicemail/send", { :body => options.to_json , :query => query }
        response.map{|item| Hashie::Mash.new(item)}
      end

    end
  end
end

