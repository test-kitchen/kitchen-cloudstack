# frozen_string_literal: true
require "base64"
require "fog/cloudstack"
require "kitchen"
require_relative "cloudstack_version"

module Kitchen
  module Driver
    class Cloudstack < Kitchen::Driver::Base
      kitchen_driver_api_version 2
      plugin_version Kitchen::Driver::CLOUDSTACK_VERSION

      default_config :server_name, nil
      default_config :server_name_prefix, nil
      default_config :cloudstack_api_url, nil
      default_config :cloudstack_api_key, nil
      default_config :cloudstack_secret_key, nil
      default_config :cloudstack_network_id, nil
      default_config :cloudstack_ssh_keypair_name, nil
      default_config :cloudstack_template_id, nil
      default_config :cloudstack_serviceoffering_id, nil
      default_config :cloudstack_zone_id, nil
      default_config :cloudstack_userdata, nil

      def config_server_name
        return if config[:server_name]

        config[:server_name] = if config[:server_name_prefix]
                                 server_name_prefix(config[:server_name_prefix])
                               else
                                 default_name
                               end
      end

      def cloudstack_api_client
        cloudstack_uri = URI.parse(config[:cloudstack_api_url])
        connection = Fog::Compute.new(
          :provider => :cloudstack,
          :cloudstack_api_key => config[:cloudstack_api_key],
          :cloudstack_secret_access_key => config[:cloudstack_secret_key],
          :cloudstack_host => cloudstack_uri.host,
          :cloudstack_port => cloudstack_uri.port,
          :cloudstack_path => cloudstack_uri.path,
          :cloudstack_project_id => config[:cloudstack_project_id],
          :cloudstack_scheme => cloudstack_uri.scheme
        )
      end

      def create(state)
        config_server_name
        if state[:server_id]
          info "#{config[:server_name]} (#{state[:server_id]}) already exists."
          return
        end

        connection = cloudstack_api_client

        server_payload = {}
        server_payload[:displayname] = config[:server_name]
        server_payload[:networkids]  = config[:cloudstack_network_id]
        server_payload[:keypair] = config[:cloudstack_ssh_keypair_name]
        server_payload[:name] = config[:server_name]
        server_payload[:templateid] = config[:cloudstack_template_id]
        server_payload[:serviceofferingid] = config[:cloudstack_serviceoffering_id]
        server_payload[:zoneid] = config[:cloudstack_zone_id]
        server_payload[:cloudstack_userdata] = Base64.encode64(config[:cloudstack_userdata]) if not config[:cloudstack_userdata].nil?

        server = connection.deploy_virtual_machine(server_payload)
        state[:server_id] = server['deployvirtualmachineresponse']['id']
        info "Cloudstack instance <#{state[:server_id]}> is starting."

        server_start = connection.query_async_job_result({
          'jobid' => server['deployvirtualmachineresponse']['jobid'],
        })
        while server_start['queryasyncjobresultresponse']['jobstatus'].to_i == 0
          sleep(5)
          server_start = connection.query_async_job_result({
            'jobid' => server['deployvirtualmachineresponse']['jobid'],
          })
        end
        if server_start['queryasyncjobresultresponse']['jobstatus'].to_i == 2
          raise ActionFailed, "Could not create server #{server_start['queryasyncjobresultresponse']['jobresult']['errortext']}"
        end
        server_info = server_start['queryasyncjobresultresponse']['jobresult']['virtualmachine']
        state[:password] = server_info['password']
        state[:hostname] = server_info['nic'][0]['ipaddress']
        info "Cloudstack instance <#{state[:server_id]}> has ip #{state[:hostname]} and is started."
        info "Cloudstack instance <#{state[:server_id]}> is booting. Waiting for ssh to be available."
        instance.transport.connection(state).wait_until_ready
        info "Cloudstack instance <#{state[:server_id]}> is fully booted and ready."
      rescue Fog::Errors::Error, Excon::Errors::Error => ex
        raise ActionFailed, ex.message
      end

      def destroy(state)
        return if state[:server_id].nil?
        connection = cloudstack_api_client
        server = connection.servers.get(state[:server_id])
        unless server.nil?
          connection.destroy_virtual_machine({
            'id' => state[:server_id],
            'expunge' => true,
          })
        end
        info "Cloudstack instance <#{state[:server_id]}> destroyed."
        state.delete(:server_id)
        state.delete(:hostname)
        state.delete(:password)
      end

      private

      def default_name
        [
          instance.name.gsub(/\W/, "")[0..14],
          ((Etc.getpwuid ? Etc.getpwuid.name : Etc.getlogin) || "nologin").gsub(/\W/, "")[0..14],
          Socket.gethostname.gsub(/\W/, "")[0..22],
          Array.new(7) { rand(36).to_s(36) }.join,
        ].join("-")
      end

      def server_name_prefix(server_name_prefix)
        if server_name_prefix.length > 54
          warn "Server name prefix too long, truncated to 54 characters"
          server_name_prefix = server_name_prefix[0..53]
        end

        server_name_prefix.gsub!(/\W/, "")

        if server_name_prefix.empty?
          warn "Server name prefix empty or invalid; using fully generated name"
          default_name
        else
          random_suffix = ("a".."z").to_a.sample(8).join
          server_name_prefix + "-" + random_suffix
        end
      end
    end
  end
end
