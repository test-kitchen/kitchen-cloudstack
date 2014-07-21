# -*- encoding: utf-8 -*-
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

require 'benchmark'
require 'kitchen'
require 'fog'
require 'socket'
require 'openssl'
# require 'pry'

module Kitchen

  module Driver

    # Cloudstack driver for Kitchen.
    #
    # @author Jeff Moody <fifthecho@gmail.com>
    class Cloudstack < Kitchen::Driver::SSHBase
      default_config :name,             nil
      default_config :username,         'root'
      default_config :port,             '22'

      def compute
        cloudstack_uri =  URI.parse(config[:cloudstack_api_url])
        connection = Fog::Compute.new(
            :provider => :cloudstack,
            :cloudstack_api_key => config[:cloudstack_api_key],
            :cloudstack_secret_access_key => config[:cloudstack_secret_key],
            :cloudstack_host => cloudstack_uri.host,
            :cloudstack_port => cloudstack_uri.port,
            :cloudstack_path => cloudstack_uri.path,
            :cloudstack_scheme => cloudstack_uri.scheme
        )
      end

      def create_server
        options = {}
        config[:server_name] ||= generate_name(instance.name)
        options['displayname'] = config[:server_name]
        if (!config[:cloudstack_network_id].nil?)
          options['networkids'] = config[:cloudstack_network_id]
        end

        if (!config[:cloudstack_security_group_id].nil?)
          options['securitygroupids'] = config[:cloudstack_security_group_id]
        end

        if (!config[:cloudstack_ssh_keypair_name].nil?)
          options['keypair'] = config[:cloudstack_ssh_keypair_name]
        end

        debug(options)
        # binding.pry
        compute.deploy_virtual_machine(config[:cloudstack_serviceoffering_id], config[:cloudstack_template_id], config[:cloudstack_zone_id], options)
      end

      def create(state)
        if not config[:name]
          # Generate what should be a unique server name
          config[:name] = "#{instance.name}-#{Etc.getlogin}-" +
              "#{Socket.gethostname}-#{Array.new(8){rand(36).to_s(36)}.join}"
        end
        if config[:disable_ssl_validation]
          require 'excon'
          Excon.defaults[:ssl_verify_peer] = false
        end

        
        server = create_server
        debug(server)

        state[:server_id] = server['deployvirtualmachineresponse'].fetch('id')
        jobid = server['deployvirtualmachineresponse'].fetch('jobid')
        info("CloudStack instance <#{state[:server_id]}> created.")
        debug("Job ID #{jobid}")

        server_start = compute.query_async_job_result(jobid)
        while server_start['queryasyncjobresultresponse'].fetch('jobstatus') == 0
          print ". "
          sleep(10)
          server_start = compute.query_async_job_result(jobid)
        end
        debug("Server_Start: #{server_start} \n")

        if server_start['queryasyncjobresultresponse'].fetch('jobstatus') == 2
          errortext = server_start['queryasyncjobresultresponse'].fetch('jobresult').fetch('errortext')
          error("ERROR! Job failed with #{errortext}")
        end

        if server_start['queryasyncjobresultresponse'].fetch('jobstatus') == 1
          server_info = server_start['queryasyncjobresultresponse']['jobresult']['virtualmachine']
          debug(server_info)
          print "(server ready)"


          keypair = nil
          password = nil
          if ((!config[:keypair_search_directory].nil?) and (File.exist?("#{config[:keypair_search_directory]}/#{config[:cloudstack_ssh_keypair_name]}.pem")))
            keypair = "#{config[:keypair_search_directory]}/#{config[:cloudstack_ssh_keypair_name]}.pem"
          elsif File.exist?("./#{config[:cloudstack_ssh_keypair_name]}.pem")
            keypair = "./#{config[:cloudstack_ssh_keypair_name]}.pem"
          elsif File.exist?("#{ENV["HOME"]}/#{config[:cloudstack_ssh_keypair_name]}.pem")
            keypair = "#{ENV["HOME"]}/#{config[:cloudstack_ssh_keypair_name]}.pem"
          elsif File.exist?("#{ENV["HOME"]}/.ssh/#{config[:cloudstack_ssh_keypair_name]}.pem")
            keypair = "#{ENV["HOME"]}/.ssh/#{config[:cloudstack_ssh_keypair_name]}.pem"
          elsif (!config[:cloudstack_ssh_keypair_name].nil?)
            info("Keypair specified but not found. Using password if enabled.")
          end

          # debug("Keypair is #{keypair}")
          state[:hostname] = config[:cloudstack_vm_public_ip] || server_info.fetch('nic').first.fetch('ipaddress')
          wait_for_sshd(state[:hostname])
          
          debug("SSH Connectivity Validated.")

          if (!keypair.nil?)
            debug("Using keypair: #{keypair}")
            info("SSH for #{state[:hostname]} with keypair #{config[:cloudstack_ssh_keypair_name]}.")
            ssh_key = File.read(keypair)
            if ssh_key.split[0] == "ssh-rsa" or ssh_key.split[0] == "ssh-dsa"
              error("SSH key #{keypair} is not a Private Key. Please modify your .kitchen.yml")
            end
            ssh = Fog::SSH.new(state[:hostname], config[:username], {:keys => keypair})
            debug(state[:hostname])
            debug(config[:username])
            debug(keypair)
          elsif (server_info.fetch('passwordenabled') == true)
            password = server_info.fetch('password')
            # Print out IP and password so you can record it if you want.
            info("Password for #{config[:username]} at #{state[:hostname]} is #{password}")
            ssh = Fog::SSH.new(state[:hostname], config[:username], {:password => password})
            debug(state[:hostname])
            debug(config[:username])
            debug(password)
          else
            info("No keypair specified (or file not found) nor is this a password enabled template. You will have to manually copy your SSH public key to #{state[:hostname]} to use this Kitchen.")
          end
          # binding.pry

          validate_ssh_connectivity(ssh)

          deploy_private_key(ssh)
        end
      end

      def destroy(state)
        return if state[:server_id].nil?

        server = compute.servers.get(state[:server_id])
        compute.destroy_virtual_machine(state[:server_id]) unless server.nil?
        info("CloudStack instance <#{state[:server_id]}> destroyed.")
        state.delete(:server_id)
        state.delete(:hostname)
      end

      def validate_ssh_connectivity(ssh)
        rescue Errno::ETIMEDOUT
          sleep 2
          false
        rescue Errno::EPERM
          false
        rescue Errno::ECONNREFUSED
          sleep 2
          false
        rescue Errno::EHOSTUNREACH
          sleep 2
          false
        rescue Errno::ENETUNREACH
          sleep 30
          false
        rescue Net::SSH::Disconnect
          sleep 15
          false
        rescue Net::SSH::AuthenticationFailed
          sleep 15
          false
        ensure
          sync_time = 45
          if (config[:cloudstack_sync_time])
            sync_time = config[:cloudstack_sync_time]
          end
          sleep(sync_time)
          debug("Connecting to host and running ls")
          ssh.run('ls')
      end

      def deploy_private_key(ssh)
        debug("Deploying user private key to server using connection #{ssh} to guarantee connectivity.")
        if File.exist?("#{ENV["HOME"]}/.ssh/id_rsa.pub")
          user_public_key = File.read("#{ENV["HOME"]}/.ssh/id_rsa.pub")
        elsif File.exist?("#{ENV["HOME"]}/.ssh/id_dsa.pub")
          user_public_key = File.read("#{ENV["HOME"]}/.ssh/id_dsa.pub")
        else
          debug("No public SSH key for user. Skipping.")
        end

        if user_public_key
          ssh.run([
                      %{mkdir .ssh},
                      %{echo "#{user_public_key}" >> ~/.ssh/authorized_keys}
                  ])
        end
      end
      
      def generate_name(base)
        # Generate what should be a unique server name
        sep = '-'
        pieces = [
          base,
          Etc.getlogin,
          Socket.gethostname,
          Array.new(8) { rand(36).to_s(36) }.join
        ]
        until pieces.join(sep).length <= 64 do
          if pieces[2].length > 24
            pieces[2] = pieces[2][0..-2]
          elsif pieces[1].length > 16
            pieces[1] = pieces[1][0..-2]
          elsif pieces[0].length > 16
            pieces[0] = pieces[0][0..-2]
          end
        end
        pieces.join sep
      end

    end
  end
end
