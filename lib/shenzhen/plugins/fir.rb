require 'json'
require 'openssl'
require 'faraday'
require 'faraday_middleware'

module Shenzhen::Plugins
  module Fir
    class Client
      HOSTNAME = 'api.fir.im'

      def initialize(user_token)
        @user_token = user_token

        @connection = Faraday.new(:url => "http://#{HOSTNAME}") do |builder|
          builder.request :url_encoded
          builder.response :json
          builder.use FaradayMiddleware::FollowRedirects
          builder.adapter :net_http
        end
      end

      def get_app_info(app_id)
        options = {
          :api_token => @user_token,
        }

        @connection.get("/apps/#{app_id}", options) do |env|
          yield env[:status], env[:body] if block_given?
        end
      rescue Faraday::Error::TimeoutError
        say_error "Timed out while geting app info." and abort
      end

      def update_app_info(app_id, options)
        options['id'] = app_id
        options['api_token'] = @user_token

        @connection.put("/apps/#{app_id}", options) do |env|
          yield env[:status], env[:body] if block_given?
        end
      rescue Faraday::Error::TimeoutError
        say_error "Timed out while geting app info." and abort
      end

      def get_upload_cert(bundle_id)
        options = {
          :type => 'ios',
          :bundle_id => bundle_id,
          :api_token => @user_token,
        }

        @connection.post("/apps", options) do |env|
          yield env[:status], env[:body] if block_given?
        end
      rescue Faraday::Error::TimeoutError
        say_error "Timed out while geting app info." and abort
      end

      def upload_build(ipa, options)

        cert_response = get_upload_cert(options['bundle_id'])
        if cert_response.status != 200
          say_error "Error getting upload cert: #{cert_response.body[:error]}"
          return
        end

        cert = cert_response.body['cert']

        connection = Faraday.new(:url => cert['binary']['upload_url'], :request => { :timeout => 360 }) do |builder|
          builder.request :multipart
          builder.response :json
          builder.use FaradayMiddleware::FollowRedirects
          builder.adapter :net_http
        end

        options = {
          :key => cert['binary']['key'],
          :token => cert['binary']['token'],
          :file => Faraday::UploadIO.new(ipa, 'application/octet-stream')
        }

        connection.post('/', options).on_complete do |env|
          yield env[:status], env[:body] if block_given?
        end
      rescue Errno::EPIPE
        say_error "Upload failed. Check internet connection is ok." and abort
      rescue Faraday::Error::TimeoutError
        say_error "Timed out while uploading build. Check https://fir.im// to see if the upload was completed." and abort
      end
    end
  end
end

command :'distribute:fir' do |c|
  c.syntax = "ipa distribute:fir [options]"
  c.summary = "Distribute an .ipa file over fir.im"
  c.description = ""
  c.option '-f', '--file FILE', ".ipa file for the build"
  c.option '-u', '--user_token TOKEN', "User Token. Available at http://fir.im/user/info"
  c.option '-a', '--app_id APPID', "App Id (iOS Bundle identifier)"
  c.option '-n', '--notes NOTES', "Release notes for the build"
  c.option '-V', '--app_version VERSION', "App Version"
  c.option '-S', '--short_version SHORT', "App Short Version"

  c.action do |args, options|
    determine_file! unless @file = options.file
    say_error "Missing or unspecified .ipa file" and abort unless @file and File.exist?(@file)

    determine_fir_user_token! unless @user_token = options.user_token || ENV['FIR_USER_TOKEN']
    say_error "Missing User Token" and abort unless @user_token

    determine_fir_app_id! unless @app_id = options.app_id || ENV['FIR_APP_ID']
    say_error "Missing App Id" and abort unless @app_id

    determine_notes! unless @notes = options.notes
    say_error "Missing release notes" and abort unless @notes

    determine_app_version! unless @app_version = options.app_version

    determine_short_version! unless @short_version = options.short_version

    client = Shenzhen::Plugins::Fir::Client.new(@user_token)
    app_response = client.get_app_info(@app_id)
    if app_response.status == 200
      app_short_uri = app_response.body['short']
      upload_response = client.upload_build(@file, app_response.body)

      if upload_response.status == 200
        say_ok "Build successfully uploaded to Fir, visit url: http://fir.im/#{app_short_uri}"
      else
        say_error "Error uploading to Fir: #{upload_response.body[:error]}" and abort
      end

    else
      say_error "Error getting app information: #{app_response.body[:error]}"
    end
  end

  private

  def determine_fir_user_token!
    @user_token ||= ask "User Token:"
  end

  def determine_fir_app_id!
    @app_id ||= ask "App Id:"
  end

  def determine_app_version!
    @app_version ||= ask "App Version:"
  end

  def determine_short_version!
    @short_version ||= ask "Short Version:"
  end
end
