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
require "fog/cloudstack"

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
        # CloudStack reports an already-deleted resource as a BadRequest with
        # this in the message. Teardown treats it as success.
        ALREADY_GONE = /does not exist/

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
          response = compute.associate_ip_address(
            "zoneid" => config[:cloudstack_zone_id],
            "vpcid" => vpc_id,
            "networkid" => config[:cloudstack_network_id]
          )
          result = client.run_response_job(response, "associateipaddressresponse")
          address = result.fetch("ipaddress")

          state[:ipaddressid] = address.fetch("id")
          create_firewall_rule(state) if config[:cloudstack_create_firewall_rule]

          address.fetch("ipaddress")
        end

        # Forwards the transport's port on the public address to the instance.
        def create_port_forward(state, virtualmachine_id)
          response = compute.create_port_forwarding_rule(
            "ipaddressid" => state[:ipaddressid],
            "privateport" => port,
            "protocol" => "TCP",
            "publicport" => port,
            "virtualmachineid" => virtualmachine_id,
            "networkid" => config[:cloudstack_network_id],
            "openfirewall" => false
          )
          state[:forwardingruleid] = response.fetch("createportforwardingruleresponse", {})["id"]
          client.run_response_job(response, "createportforwardingruleresponse")
        end

        # Removes everything {#associate_public_ip} and {#create_port_forward}
        # created, in the reverse order, tolerating resources already gone.
        def teardown(state)
          delete_port_forward(state) if state[:forwardingruleid]
          delete_firewall_rule(state) if state[:firewall_rule_id]
          release_public_ip(state) if state[:ipaddressid]
        end

        private

        attr_reader :config, :client, :port, :logger

        # @return [Fog::Compute] the shared CloudStack connection
        def compute = client.compute

        # Opens the transport's port on the allocated public address.
        #
        # @param state [Hash] mutable instance state; gains +firewall_rule_id+
        # @return [void]
        def create_firewall_rule(state)
          response = compute.create_firewall_rule(
            "projectid" => config[:cloudstack_project_id],
            "cidrlist" => config[:cloudstack_firewall_cidr] || "0.0.0.0/0",
            "protocol" => "tcp",
            "startport" => port,
            "endport" => port,
            "ipaddressid" => state[:ipaddressid]
          )
          result = client.run_response_job(response, "createfirewallruleresponse")
          rule = result["firewallrule"]
          state[:firewall_rule_id] = rule["id"] if rule.is_a?(Hash)
        end

        # Removes the port forwarding rule, tolerating one already gone.
        #
        # @param state [Hash] instance state naming the rule
        # @return [void]
        def delete_port_forward(state)
          tolerating_missing("port forwarding rule") do
            response = compute.delete_port_forwarding_rule(state[:forwardingruleid])
            client.run_response_job(response, "deleteportforwardingruleresponse")
          end
        end

        # Removes the firewall rule, tolerating one already gone.
        #
        # @param state [Hash] instance state naming the rule
        # @return [void]
        def delete_firewall_rule(state)
          tolerating_missing("firewall rule") do
            response = compute.delete_firewall_rule(state[:firewall_rule_id])
            client.run_response_job(response, "deletefirewallruleresponse")
          end
        end

        # Disassociates the public address, tolerating one already gone.
        #
        # @param state [Hash] instance state naming the address
        # @return [void]
        def release_public_ip(state)
          tolerating_missing("public IP address") do
            response = compute.disassociate_ip_address(state[:ipaddressid])
            client.run_response_job(response, "disassociateipaddressresponse")
          end
        end

        # Teardown should not fail because something is already deleted, but
        # any other API error is worth surfacing.
        def tolerating_missing(description)
          yield
        rescue Fog::Cloudstack::Compute::BadRequest => e
          raise unless e.to_s.match?(ALREADY_GONE)

          logger&.debug("CloudStack #{description} was already gone: #{e}")
        end

        # A VPC network needs its vpcid passed when allocating an address.
        def vpc_id
          networks = compute.list_networks.fetch("listnetworksresponse", {})["network"]
          return nil unless networks.is_a?(Array)

          network = networks.find { |n| n["id"] == config[:cloudstack_network_id] }
          network && network["vpcid"]
        end
      end
    end
  end
end
