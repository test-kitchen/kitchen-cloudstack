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

require "kitchen/driver/base"
require "cloudstack_client"
require_relative "client"

module Kitchen
  module Driver
    class Cloudstack < Kitchen::Driver::Base
      # Manages the optional public address a instance is reached through:
      # associating an address, forwarding a port to the instance, opening the
      # firewall, and undoing all of it on teardown.
      #
      # The port forwarded and opened is the port the configured Test Kitchen
      # transport connects on, so a WinRM instance gets 5985 rather than SSH's
      # 22 without any extra configuration.
      class Networking
        # CloudStack reports an already-deleted resource as an API error with
        # this in the message. Teardown treats it as success.
        ALREADY_GONE = /does not exist/

        # @param config [Hash] the driver configuration
        # @param client [Client] the shared CloudStack client
        # @param port [Integer] the transport port to forward and open
        # @param logger [#debug, nil] where already-gone resources are noted
        def initialize(config, client:, port:, logger: nil)
          @config = config
          @client = client
          @port = port
          @logger = logger
        end

        # Allocates a public address and, if requested, opens the firewall.
        #
        # @param state [Hash] mutable instance state
        # @return [String] the allocated public IP address
        def associate_public_ip(state)
          response = api.associate_ip_address({
            "zoneid" => config[:cloudstack_zone_id],
            "vpcid" => vpc_id,
            "networkid" => config[:cloudstack_network_id],
            "projectid" => config[:cloudstack_project_id],
          }, Client::SYNC)
          result = client.run_job(response.fetch("jobid"))
          address = result.fetch("ipaddress")

          state[:ipaddressid] = address.fetch("id")
          create_firewall_rule(state) if config[:cloudstack_create_firewall_rule]

          address.fetch("ipaddress")
        end

        # Forwards the transport's port on the public address to the instance.
        #
        # @param state [Hash] mutable instance state; gains +forwardingruleid+
        # @param virtualmachine_id [String] the instance to forward to
        # @return [void]
        def create_port_forward(state, virtualmachine_id)
          response = api.create_port_forwarding_rule({
            "ipaddressid" => state[:ipaddressid],
            "privateport" => port,
            "protocol" => "TCP",
            "publicport" => port,
            "virtualmachineid" => virtualmachine_id,
            "networkid" => config[:cloudstack_network_id],
            # cloudstack_client drops falsey argument values, and CloudStack
            # defaults this to true on a non-VPC network, so a boolean false
            # here would let CloudStack open the firewall itself -- creating a
            # rule teardown does not know about.
            "openfirewall" => "false",
          }, Client::SYNC)
          state[:forwardingruleid] = response["id"]
          client.run_job(response.fetch("jobid"))
        end

        # Removes everything {#associate_public_ip} and {#create_port_forward}
        # created, in the reverse order, tolerating resources already gone.
        #
        # @param state [Hash] instance state naming the resources to remove
        # @return [void]
        def teardown(state)
          delete_port_forward(state) if state[:forwardingruleid]
          delete_firewall_rule(state) if state[:firewall_rule_id]
          release_public_ip(state) if state[:ipaddressid]
        end

        private

        attr_reader :config, :client, :port, :logger

        # @return [CloudstackClient::Client] the shared CloudStack connection
        def api = client.api

        # Opens the transport's port on the allocated public address.
        #
        # @param state [Hash] mutable instance state; gains +firewall_rule_id+
        # @return [void]
        def create_firewall_rule(state)
          response = api.create_firewall_rule({
            "cidrlist" => config[:cloudstack_firewall_cidr] || "0.0.0.0/0",
            "protocol" => "tcp",
            "startport" => port,
            "endport" => port,
            "ipaddressid" => state[:ipaddressid],
          }, Client::SYNC)
          result = client.run_job(response.fetch("jobid"))
          rule = result["firewallrule"]
          state[:firewall_rule_id] = rule["id"] if rule.is_a?(Hash)
        end

        # Removes the port forwarding rule, tolerating one already gone.
        #
        # @param state [Hash] instance state naming the rule
        # @return [void]
        def delete_port_forward(state)
          tolerating_missing("port forwarding rule") do
            response = api.delete_port_forwarding_rule({ "id" => state[:forwardingruleid] }, Client::SYNC)
            client.run_job(response.fetch("jobid"))
          end
        end

        # Removes the firewall rule, tolerating one already gone.
        #
        # @param state [Hash] instance state naming the rule
        # @return [void]
        def delete_firewall_rule(state)
          tolerating_missing("firewall rule") do
            response = api.delete_firewall_rule({ "id" => state[:firewall_rule_id] }, Client::SYNC)
            client.run_job(response.fetch("jobid"))
          end
        end

        # Disassociates the public address, tolerating one already gone.
        #
        # @param state [Hash] instance state naming the address
        # @return [void]
        def release_public_ip(state)
          tolerating_missing("public IP address") do
            response = api.disassociate_ip_address({ "id" => state[:ipaddressid] }, Client::SYNC)
            client.run_job(response.fetch("jobid"))
          end
        end

        # Teardown should not fail because something is already deleted, but
        # any other API error is worth surfacing.
        #
        # @param description [String] names the resource, for the debug message
        # @yield the deletion call to attempt
        # @return [void]
        # @raise [CloudstackClient::ApiError] for any error other than the
        #   resource already being gone
        def tolerating_missing(description)
          yield
        rescue CloudstackClient::ApiError => e
          raise unless e.to_s.match?(ALREADY_GONE)

          logger&.debug("CloudStack #{description} was already gone: #{e}")
        end

        # A VPC network needs its vpcid passed when allocating an address.
        def vpc_id
          networks = api.list_networks("projectid" => config[:cloudstack_project_id])
          return nil unless networks.is_a?(Array)

          network = networks.find { |n| n["id"] == config[:cloudstack_network_id] }
          network && network["vpcid"]
        end
      end
    end
  end
end
