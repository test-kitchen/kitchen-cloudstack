# -*- encoding: utf-8 -*-
# frozen_string_literal: true
#
# Author:: Jeff Moody (<fifthecho@gmail.com>)
#
# Copyright (C) 2013, Jeff Moody
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "base64"
require "fog/cloudstack"
require "kitchen"
require_relative "cloudstack_version"

module Kitchen
  module Driver
    # Cloudstack driver for Kitchen.
    #
    # @author Jeff Moody <fifthecho@gmail.com>
    class Cloudstack < Kitchen::Driver::Base
      kitchen_driver_api_version 2
      plugin_version Kitchen::Driver::CLOUDSTACK_VERSION

      default_config :server_name, nil
      default_config :server_name_prefix, nil
      default_config :cloudstack_api_url, nil
      default_config :cloudstack_api_key, nil
      default_config :cloudstack_secret_key, nil
      default_config :cloudstack_network_id, nil
      default_config :cloudstack_network, nil
      default_config :cloudstack_ssh_keypair_name, nil
      default_config :cloudstack_template_id, nil
      default_config :cloudstack_template, nil
      default_config :cloudstack_service_offering_id, nil
      default_config :cloudstack_service_offering, nil
      default_config :cloudstack_zone_id, nil
      default_config :cloudstack_zone, nil
      default_config :cloudstack_rootdisksize, nil
      default_config :cloudstack_userdata, nil
      default_config :cloudstack_post_install_script, nil

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
        api_client = Fog::Compute.new(
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

        server_payload = generate_server_payload
        server_info = create_instance(server_payload)

        state[:server_id] = server_info['id']
        state[:password] = server_info['password']
        state[:hostname] = server_info['nic'][0]['ipaddress']

        info "Cloudstack instance <#{state[:server_id]}> has ip #{state[:hostname]} and password #{state[:password]}"

        wait_for_instance_reachable(state)

        info "Cloudstack instance <#{state[:server_id]}> is fully booted and ready."
      rescue Fog::Errors::Error, Excon::Errors::Error => ex
        raise ActionFailed, ex.message
      end

      def generate_server_payload
        api_client = cloudstack_api_client
        server_payload = {
          :displayname => config[:server_name],
          :networkids => get_network_id(api_client),
          :keypair => config[:cloudstack_ssh_keypair_name],
          :name => config[:server_name],
          :templateid => get_template_id(api_client),
          :serviceofferingid => get_service_offering_id(api_client),
          :zoneid => get_zone_id(api_client),
        }
        if not config[:cloudstack_userdata].nil?
          server_payload[:cloudstack_userdata] = Base64.encode64(config[:cloudstack_userdata])
        end
        if not config[:cloudstack_rootdisksize].nil?
          server_payload[:rootdisksize] = config[:cloudstack_rootdisksize].to_s.gsub(/\s?GB$/, '').to_i
        end
        server_payload
      end

      def create_instance(server_payload)
        api_client = cloudstack_api_client

        server = api_client.deploy_virtual_machine(server_payload)
        info "Cloudstack instance <#{server['deployvirtualmachineresponse']['id']}> is starting."

        server_start = api_client.query_async_job_result({
          'jobid' => server['deployvirtualmachineresponse']['jobid'],
        })
        while server_start['queryasyncjobresultresponse']['jobstatus'].to_i == 0
          sleep(5)
          server_start = api_client.query_async_job_result({
            'jobid' => server['deployvirtualmachineresponse']['jobid'],
          })
        end
        if server_start['queryasyncjobresultresponse']['jobstatus'].to_i == 2
          raise ActionFailed, "Could not create server #{server_start['queryasyncjobresultresponse']['jobresult']['errortext']}"
        end

        server_start['queryasyncjobresultresponse']['jobresult']['virtualmachine']
      end

      def wait_for_instance_reachable(state)
        info "Waiting for the machine to finish booting and to be remotely accessible."

        remote_connection = instance.transport.connection(state)
        remote_connection.wait_until_ready

        if not config[:cloudstack_post_install_script].nil?
          remote_connection.execute(config[:cloudstack_post_install_script])
          remote_connection.close()
        end
      end

      def destroy(state)
        return if state[:server_id].nil?
        api_client = cloudstack_api_client
        server = api_client.servers.get(state[:server_id])
        unless server.nil?
          api_client.destroy_virtual_machine({
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

      def get_zone_id(api_client)
        if not config[:cloudstack_zone_id].nil?
          return config[:cloudstack_zone_id]
        end
        zones = api_client.list_zones({:name => config[:cloudstack_zone]})
        zones['listzonesresponse']['zone'][0]['id']
      end

      def get_template_id(api_client)
        if not config[:cloudstack_template_id].nil?
          return config[:cloudstack_template_id]
        end
        templates = api_client.list_templates({:name => config[:cloudstack_template], :templatefilter => 'all'})
        templates['listtemplatesresponse']['template'][0]['id']
      end

      def get_service_offering_id(api_client)
        if not config[:cloudstack_service_offering_id].nil?
          return config[:cloudstack_service_offering_id]
        end
        service_offerings = api_client.list_service_offerings({:name => config[:cloudstack_service_offering]})
        service_offerings['listserviceofferingsresponse']['serviceoffering'][0]['id']
      end

      def get_network_id(api_client)
        if not config[:cloudstack_network_id].nil?
          return config[:cloudstack_network_id]
        end
        networks = api_client.list_networks({:name => config[:cloudstack_network]})
        networks['listnetworksresponse']['network'][0]['id']
      end
    end
  end
end
