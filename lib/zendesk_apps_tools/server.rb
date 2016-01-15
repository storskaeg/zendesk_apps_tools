require 'sinatra/base'
require 'xat_support/package'

module ZendeskAppsTools
  class Server < Sinatra::Base
    set :protection, :except => :frame_options
    last_mtime = Time.new(0)
    ZENDESK_DOMAINS_REGEX = /^http(?:s)?:\/\/[a-z0-9-]+\.(?:zendesk|zopim|zd-(?:dev|master|staging))\.com$/
    last_domain = nil

    get '/app.js' do
      access_control_allow_origin
      content_type 'text/javascript'

      settings_helper = ZendeskAppsTools::Settings.new

      appsjs = []
      installations = []
      order = {}

      settings.apps.each_with_index do |app, index|
        package = app[:package]
        app_id = installation_id = -(index+1)
        app_name = package.manifest_json['name'] || 'Local App'

        appsjs << package.compile_js(
          app_name: app_name,
          app_id: app_id,
          assets_dir: "http://localhost:#{settings.port}/#{app_id}/",
          locale: params['locale']
        )

        location = begin
          locations = package.manifest_json['location']
          locations = [ locations ] if locations.is_a?(String)
          locations.is_a?(Hash) ? locations : { zendesk: locations }
        end

        location.each do |_, locations|
          locations = [ locations ] if locations.is_a?(String)
          locations.each do |loc|
            order[loc] ||= []
            order[loc] << app_id
          end
        end

        if app[:settings_file_path]
          curr_mtime = File.stat(app[:settings_file_path]).mtime
          curr_domain = params['subdomain']
          if (curr_mtime > last_mtime || curr_domain != last_domain)
            app[:settings] = settings_helper.get_settings_from_file(app[:settings_file_path], app[:package].manifest_json['parameters'], params['subdomain'])
            last_mtime = File.stat(app[:settings_file_path]).mtime
            last_domain = curr_domain
          end
        end

        installations << ZendeskAppsSupport::Installation.new(
          id: installation_id,
          app_id: app_id,
          app_name: app_name,
          enabled: true,
          requirements: package.requirements_json,
          settings: app[:settings].merge({title: app_name}),
          updated_at: Time.now.iso8601,
          created_at: Time.now.iso8601
        )
      end

      installed = ZendeskAppsSupport::Installed.new(appsjs, installations)
      installed.compile_js(installation_orders: order)
    end

    get "/:app_id/:file" do |app_id, file|
      # convert to postive and substract 1. So -1 => 0, -3 => 2, etc
      index = (-app_id.to_i)-1
      send_file File.join(settings.apps[index][:package].root, 'assets', file)
    end

    get "/:file" do |file|
      access_control_allow_origin
      send_file File.join(settings.root, 'assets', file)
    end

    # This is for any preflight request
    # It reads 'Access-Control-Request-Headers' to set 'Access-Control-Allow-Headers'
    # And also sets 'Access-Control-Allow-Origin' header
    options "*" do
      access_control_allow_origin
      headers 'Access-Control-Allow-Headers' => request.env['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'] if request.env['HTTP_ORIGIN'] =~ ZENDESK_DOMAINS_REGEX
    end

    # This sets the 'Access-Control-Allow-Origin' header for requests coming from zendesk
    def access_control_allow_origin
      origin = request.env['HTTP_ORIGIN']
      headers 'Access-Control-Allow-Origin' => origin if origin =~ ZENDESK_DOMAINS_REGEX
    end
  end
end
