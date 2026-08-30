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

        # Problems found while resolving credentials, worth telling the user
        # about but not worth failing over.
        #
        # @return [Array<String>] messages collected so far, empty until
        #   {#to_state} has run
        attr_reader :warnings

        # @param config [Hash] the driver configuration
        # @param home [String, nil] the home directory keypair paths expand against
        # @param working_dir [String] the directory relative keypair paths expand against
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

        # Picks the single credential the transport should use.
        #
        # Sources are tried in {SOURCES} order and the first that resolves
        # wins, so a keypair beats a CloudStack-generated password, which in
        # turn beats a password from config.
        #
        # @param server_info [Hash] the "virtualmachine" payload
        # @return [Hash] one of +{ssh_key:}+, +{password:}+, or +{}+
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

        # The password CloudStack generated for a password-enabled template.
        #
        # @param server_info [Hash] the "virtualmachine" payload
        # @return [String, nil] nil unless the template is password-enabled
        def generated_password(server_info)
          return nil unless server_info["passwordenabled"]

          server_info["password"]
        end

        # CloudStack keypairs are matched to a local <name>.pem file. Look in
        # the configured directory first, then the conventional locations.
        #
        # Memoized, including the nil result, so the filesystem is searched
        # once and a missing key is only warned about once.
        #
        # @return [String, nil] path to the private key, or nil when no
        #   keypair is configured or no matching .pem was found
        def keypair_path
          return @keypair_path if defined?(@keypair_path)

          @keypair_path = find_keypair
        end

        # Locates the local .pem matching the configured keypair name.
        #
        # A missing file is a warning rather than an error, because a password
        # may still get the user in.
        #
        # @return [String, nil] path to the key, or nil if none was found
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

        # Directories searched for a keypair's .pem, in order.
        #
        # @return [Array<String>] the configured directory, the working
        #   directory, the home directory, then ~/.ssh
        def search_directories
          [config[:keypair_search_directory], working_dir, home, File.join(home.to_s, ".ssh")].compact
        end

        # Warns when the located .pem is a public key.
        #
        # Exporting the wrong half of a keypair is a common mistake, and the
        # resulting authentication failure is otherwise hard to read.
        #
        # @param path [String] the key file to inspect
        # @return [void]
        def warn_unless_private_key(path)
          first_token = File.read(path).split.first
          return unless PUBLIC_KEY_PREFIXES.include?(first_token)

          warnings << "SSH key #{path} is not a private key. Please check your kitchen.yml."
        end

        # Types for the private readers above. YARD only honours an attribute
        # directive that comes after the attr_reader statement, and attaching
        # one directly to the statement documents only its first name, so the
        # three are documented together down here instead.

        # @!attribute [r] config
        #   @return [Hash] the driver configuration

        # @!attribute [r] home
        #   @return [String, nil] the home directory keypair paths expand
        #     against

        # @!attribute [r] working_dir
        #   @return [String] the directory relative keypair paths expand
        #     against
      end
    end
  end
end
