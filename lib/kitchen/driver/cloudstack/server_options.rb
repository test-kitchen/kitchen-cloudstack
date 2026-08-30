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
require "base64" unless defined?(Base64)
require "etc" unless defined?(Etc)
require "socket" unless defined?(Socket)

module Kitchen
  module Driver
    class Cloudstack < Kitchen::Driver::Base
      # Builds the parameter hash for CloudStack's deployVirtualMachine call.
      #
      # Kept free of any API or Test Kitchen state so it can be exercised
      # directly: given config in, parameters out.
      class ServerOptions
        # CloudStack rejects instance names longer than this.
        MAX_NAME_LENGTH = 64

        # Random suffix appended to generated names, plus its separator.
        SUFFIX_LENGTH = 8

        # Optional parameters, keyed by the CloudStack parameter name. Any
        # entry whose config value is nil is dropped before the call.
        OPTIONAL_PARAMS = {
          "networkids" => :cloudstack_network_id,
          "securitygroupids" => :cloudstack_security_group_id,
          "affinitygroupids" => :cloudstack_affinity_group_id,
          "keypair" => :cloudstack_ssh_keypair_name,
          "diskofferingid" => :cloudstack_diskoffering_id,
          "size" => :cloudstack_diskoffering_size,
          "name" => :host_name,
          "details[0].cpuNumber" => :cloudstack_serviceoffering_cpu,
          "details[0].cpuSpeed" => :cloudstack_serviceoffering_cpuspeed,
          "details[0].memory" => :cloudstack_serviceoffering_memory,
        }.freeze

        # Matches a string that is already valid base64, so user data supplied
        # pre-encoded is passed through rather than double-encoded.
        #
        # Anchored with \A and \z rather than ^ and $, which in Ruby anchor to
        # a line: a single blank line anywhere in the user data used to satisfy
        # the whole pattern, and cloud-config and shell scripts are full of
        # blank lines. At least one group is required so the empty string does
        # not count as pre-encoded either.
        #
        # A short word made only of base64 characters is genuinely ambiguous
        # and is still passed through; there is no way to tell it apart from
        # data someone encoded themselves.
        BASE64_PATTERN = %r{
          \A
          (?:[A-Za-z0-9+/]{4}\n?)*
          (?:[A-Za-z0-9+/]{4}|[A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)
          \n?\z
        }x

        # @param config [Hash] the driver configuration
        # @param instance_name [String] the Test Kitchen instance name
        # @param login [String] the local username, used in the generated name
        # @param hostname [String] the local hostname, used in the generated name
        def initialize(config, instance_name:, login: Etc.getlogin, hostname: Socket.gethostname)
          @config = config
          @instance_name = instance_name
          @login = login
          @hostname = hostname
        end

        # Builds the parameter hash for deployVirtualMachine.
        #
        # Optional parameters whose config value is nil are dropped, so
        # CloudStack applies its own defaults rather than receiving nils.
        #
        # @return [Hash] parameters ready to pass to the API
        def to_h
          params = { "displayname" => display_name }

          OPTIONAL_PARAMS.each do |param, config_key|
            value = config[config_key]
            params[param] = value unless value.nil?
          end

          params[:userdata] = userdata if config[:cloudstack_userdata]

          params[:templateid] = config[:cloudstack_template_id]
          params[:serviceofferingid] = config[:cloudstack_serviceoffering_id]
          params[:zoneid] = config[:cloudstack_zone_id]
          params
        end

        # The instance's display name.
        #
        # @return [String] the configured +server_name+, or a generated one
        def display_name
          config[:server_name] || generate_name
        end

        private

        attr_reader :config, :instance_name, :login, :hostname

        # Builds a name that is unique per run and short enough for CloudStack.
        #
        # The three descriptive parts are truncated proportionally until the
        # whole name fits, so an oversized login or hostname cannot push the
        # result over the limit.
        def generate_name
          suffix = Array.new(SUFFIX_LENGTH) { rand(36).to_s(36) }.join
          parts = [instance_name, login, hostname].compact.reject(&:empty?)

          budget = MAX_NAME_LENGTH - suffix.length - parts.length
          parts = truncate_to_budget(parts, budget)

          (parts + [suffix]).join("-")
        end

        # Shortens the longest part repeatedly until the parts fit the budget,
        # which keeps the shorter, more identifying parts intact.
        #
        # @param parts [Array<String>] the name components
        # @param budget [Integer] the total characters the parts may occupy
        # @return [Array<String>] the components, shortened to fit
        def truncate_to_budget(parts, budget)
          parts = parts.dup
          while parts.sum(&:length) > budget
            longest = parts.each_with_index.max_by { |part, _i| part.length }
            break if longest.first.length <= 1

            parts[longest.last] = longest.first[0..-2]
          end
          parts
        end

        # The user data to send, base64 encoded.
        #
        # Data that is already valid base64 is passed through untouched rather
        # than being encoded a second time. Encoding is strict so the result
        # is one line: Base64.encode64 wraps at 60 characters, and those line
        # breaks would go out inside an API query parameter.
        #
        # @return [String] base64-encoded user data
        def userdata
          data = config[:cloudstack_userdata]
          data.match?(BASE64_PATTERN) ? data : Base64.strict_encode64(data)
        end
      end
    end
  end
end
