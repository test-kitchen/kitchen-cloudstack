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

module Kitchen
  module Driver
    class Cloudstack < Kitchen::Driver::Base
      # Works out which credentials Test Kitchen's transport should use, and
      # returns them as the subset of instance state the transport reads.
      #
      # Anything placed in state overrides the user's `transport:` config,
      # because the transport merges state over its own configuration. So
      # username and port are only emitted when the driver was explicitly
      # configured with them; otherwise the transport's own settings win.
      class Credentials
        # Credential sources, in the order they take precedence.
        SOURCES = %i{keypair generated_password configured_password}.freeze

        # A pem file starting with one of these is a public key, which will
        # never authenticate. Users hit this by exporting the wrong half.
        PUBLIC_KEY_PREFIXES = %w{ssh-rsa ssh-dsa ssh-ed25519 ecdsa-sha2-nistp256}.freeze

        attr_reader :warnings

        def initialize(config, home: ENV["HOME"], working_dir: ".")
          @config = config
          @home = home
          @working_dir = working_dir
          @warnings = []
        end

        # @param server_info [Hash] the "virtualmachine" payload from CloudStack
        # @return [Hash] state keys for the transport, credentials included
        def to_state(server_info)
          state = {}
          state[:username] = config[:username] if config[:username]
          state[:port] = config[:port] if config[:port]
          state.merge(credential_state(server_info))
        end

        private

        attr_reader :config, :home, :working_dir

        def credential_state(server_info)
          if keypair_path
            { ssh_key: keypair_path }
          elsif (password = generated_password(server_info))
            { password: password }
          elsif config[:password]
            { password: config[:password] }
          else
            {}
          end
        end

        def generated_password(server_info)
          return nil unless server_info["passwordenabled"]

          server_info["password"]
        end

        # CloudStack keypairs are matched to a local <name>.pem file. Look in
        # the configured directory first, then the conventional locations.
        def keypair_path
          return @keypair_path if defined?(@keypair_path)

          @keypair_path = find_keypair
        end

        def find_keypair
          name = config[:cloudstack_ssh_keypair_name]
          return nil if name.nil?

          path = search_directories.map { |dir| File.join(dir, "#{name}.pem") }
            .find { |candidate| File.exist?(candidate) }

          if path
            warn_unless_private_key(path)
          else
            warnings << "Keypair #{name} specified but no #{name}.pem was found. " \
              "Using a password if one is available."
          end

          path
        end

        def search_directories
          [config[:keypair_search_directory], working_dir, home, File.join(home.to_s, ".ssh")].compact
        end

        def warn_unless_private_key(path)
          first_token = File.read(path).split.first
          return unless PUBLIC_KEY_PREFIXES.include?(first_token)

          warnings << "SSH key #{path} is not a private key. Please check your kitchen.yml."
        end
      end
    end
  end
end
