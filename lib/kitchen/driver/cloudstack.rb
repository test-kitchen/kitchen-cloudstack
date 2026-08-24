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

require "kitchen"
require "kitchen/driver/base"
require "time" unless defined?(Time.zone_offset)

require_relative "cloudstack_version"
require_relative "cloudstack/client"
require_relative "cloudstack/credentials"
require_relative "cloudstack/networking"
require_relative "cloudstack/server_options"

module Kitchen
  # Test Kitchen's driver plugins.
  module Driver
    # Test Kitchen driver for Apache CloudStack and Citrix CloudPlatform.
    #
    # The driver's job is to create the instance, tell Test Kitchen how to
    # reach it, and destroy it again. Talking to the instance is the
    # transport's job, so the driver hands over credentials through instance
    # state and lets the configured transport connect -- which is what makes
    # a WinRM instance work as readily as an SSH one.
    #
    # @author Jeff Moody <fifthecho@gmail.com>
    class Cloudstack < Kitchen::Driver::Base
      kitchen_driver_api_version 2

      plugin_version Kitchen::Driver::CLOUDSTACK_VERSION

      default_config :cloudstack_create_firewall_rule, false
      default_config :cloudstack_expunge, false
      default_config :associate_public_ip, false

      # CloudStack instance states that mean the machine is actually up.
      LIVE_STATES = %w{Running Starting}.freeze

      # State this driver owns, cleared on destroy. Credentials are included
      # so a destroyed instance leaves no password behind in the state file.
      STATE_KEYS = %i{
        server_id hostname ipaddressid forwardingruleid firewall_rule_id
        username port password ssh_key
      }.freeze

      # Deploys the instance and waits until it can be logged into.
      #
      # @param state [Hash] mutable instance state; gains +server_id+,
      #   +hostname+, and whichever credential keys apply
      # @return [void]
      def create(state)
        super
        disable_ssl_validation! if config[:disable_ssl_validation]

        server_info = deploy_instance(state)

        state[:hostname] = hostname_for(state, server_info)
        apply_credentials(state, server_info)

        wait_for_guest_password_sync
        instance.transport.connection(state).wait_until_ready
      end

      # Destroys the instance and releases anything allocated alongside it.
      #
      # Public addresses, port forwards, and firewall rules are torn down
      # first, then every key this driver owns is cleared from state so a
      # destroyed instance leaves no password behind in the state file.
      #
      # @param state [Hash] instance state naming the instance
      # @return [void]
      def destroy(state)
        return unless state[:server_id]

        networking.teardown(state) if config[:associate_public_ip]

        client.compute.destroy_virtual_machine(
          "id" => state[:server_id],
          "expunge" => !!config[:cloudstack_expunge]
        )
        info("CloudStack instance <#{state[:server_id]}> destroyed.")

        STATE_KEYS.each { |key| state.delete(key) }
      end

      # Reports what CloudStack currently thinks of the instance.
      #
      # @param state [Hash] instance state naming the instance
      # @return [Hash] a Test Kitchen status hash, or the base implementation's
      #   answer when there is no instance or CloudStack does not know it
      def status(state)
        return super unless state[:server_id]

        instance_state = lookup_instance_state(state[:server_id])
        return super unless instance_state

        {
          live: LIVE_STATES.include?(instance_state),
          state: instance_state,
          source: "driver",
          resource_id: state[:server_id],
          message: "CloudStack reports the instance as #{instance_state}",
          checked_at: Time.now.utc.iso8601,
        }
      end

      # The CloudStack API connection, exposed so it can be substituted.
      #
      # @return [Client]
      def client
        @client ||= Client.new(config)
      end

      private

      # Deploys the instance and waits for CloudStack to finish building it.
      #
      # @param state [Hash] mutable instance state; gains +server_id+
      # @return [Hash] the "virtualmachine" payload describing the instance
      def deploy_instance(state)
        options = ServerOptions.new(config, instance_name: instance.name).to_h
        debug("Deploying CloudStack instance with #{options}")

        response = client.compute.deploy_virtual_machine(options)
          .fetch("deployvirtualmachineresponse")

        state[:server_id] = response.fetch("id")
        info("CloudStack instance <#{state[:server_id]}> created.")

        client.run_job(response.fetch("jobid")).fetch("virtualmachine")
      end

      # Works out the address Test Kitchen should connect to, allocating a
      # public address and forwarding the transport's port when asked to.
      #
      # @param state [Hash] mutable instance state; gains +ipaddressid+ and
      #   +forwardingruleid+ when a public address is associated
      # @param server_info [Hash] the "virtualmachine" payload from CloudStack
      # @return [String] the address the transport should connect to
      def hostname_for(state, server_info)
        unless config[:associate_public_ip]
          return config[:cloudstack_vm_public_ip] ||
              server_info.fetch("nic").first.fetch("ipaddress")
        end

        info("Associating public IP address...")
        address = networking.associate_public_ip(state)

        info("Forwarding port #{transport_port} to the instance...")
        networking.create_port_forward(state, server_info.fetch("id"))

        address
      end

      # Credentials go into state because the transport merges state over its
      # own config, so this is how a driver tells the transport how to log in.
      #
      # @param state [Hash] mutable instance state; gains the credential keys
      # @param server_info [Hash] the "virtualmachine" payload from CloudStack
      # @return [void]
      def apply_credentials(state, server_info)
        credentials = Credentials.new(config)
        state.merge!(credentials.to_state(server_info))
        credentials.warnings.each { |warning| warn(warning) }

        if state[:ssh_key]
          info("Connecting to #{state[:hostname]} with keypair #{state[:ssh_key]}")
        elsif state[:password]
          info("Connecting to #{state[:hostname]} with a password")
        else
          warn("No keypair or password is available for #{state[:hostname]}. " \
            "You may need to copy your public key to the instance yourself.")
        end
      end

      # CloudStack's cloud-set-guest-password and SSH key injection can land
      # after the network is up, so allow configuring a settling period.
      def wait_for_guest_password_sync
        sync_time = config[:cloudstack_sync_time]
        return unless sync_time

        debug("Waiting #{sync_time}s for CloudStack to finish setting credentials")
        sleep(sync_time)
      end

      # Asks CloudStack for one instance's current state.
      #
      # @param server_id [String] the instance's CloudStack id
      # @return [String, nil] e.g. +"Running"+, or nil when CloudStack returns
      #   no matching machine
      def lookup_instance_state(server_id)
        response = client.compute.list_virtual_machines("id" => server_id)
        machines = response.fetch("listvirtualmachinesresponse", {})["virtualmachine"]
        return nil unless machines.is_a?(Array) && !machines.empty?

        machines.first["state"]
      end

      # Helper that owns the optional public address and its firewall rules.
      #
      # @return [Networking]
      def networking
        @networking ||= Networking.new(
          config, client: client, port: transport_port, logger: logger
        )
      end

      # The port the configured transport connects on: 22 for SSH, 5985 or
      # 5986 for WinRM. Port forwarding and firewall rules follow it.
      def transport_port
        instance.transport[:port]
      end

      # Turns off TLS certificate verification for every Excon request.
      #
      # This is process-wide, not scoped to this driver, which is why it is
      # only done when +disable_ssl_validation+ is explicitly set.
      #
      # @return [void]
      def disable_ssl_validation!
        require "excon" unless defined?(Excon)
        Excon.defaults[:ssl_verify_peer] = false
      end
    end
  end
end
