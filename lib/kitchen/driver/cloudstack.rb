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
require 'net/ssh/multi'

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
        options['zoneid'] = config[:cloudstack_zone_id]
        options['templateid'] = config[:cloudstack_template_id]
        options['displayname'] = config[:name]
        options['serviceofferingid'] = config[:cloudstack_serviceoffering_id]
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
        compute.deploy_virtual_machine(options)
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

        server_start = compute.query_async_job_result('jobid'=>jobid)
        while server_start['queryasyncjobresultresponse'].fetch('jobstatus') == 0
          print ". "
          sleep(10)
          server_start = compute.query_async_job_result('jobid'=>jobid)
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
          elsif File.exist?("~/#{config[:cloudstack_ssh_keypair_name]}.pem")
            keypair = "~/#{config[:cloudstack_ssh_keypair_name]}.pem"
          elsif File.exist?("~/.ssh/#{config[:cloudstack_ssh_keypair_name]}.pem")
            keypair = "~/.ssh/#{config[:cloudstack_ssh_keypair_name]}.pem"
          elsif (!config[:cloudstack_ssh_keypair_name].nil?)
            info("Keypair specified but not found. Using password if enabled.")
          end

          # debug("Keypair is #{keypair}")
          state[:hostname] = server_info.fetch('nic').first.fetch('ipaddress')

          if (!keypair.nil?)
            debug("Using keypair: #{keypair}")
            info("SSH for #{state[:hostname]} with keypair #{config[:cloudstack_ssh_keypair_name]}.")
            ssh = Fog::SSH.new(state[:hostname], config[:username], {:keys => keypair})
            debug(state[:hostname])
            debug(config[:username])
            debug(keypair)
            deploy_private_key(state[:hostname], ssh)
          elsif (server_info.fetch('passwordenabled') == true)
            password = server_info.fetch('password')
            # Print out IP and password so you can record it if you want.
            info("Password for #{config[:username]} at #{state[:hostname]} is #{password}")
            ssh = Fog::SSH.new(state[:hostname], config[:username], {:password => password})
            debug(state[:hostname])
            debug(config[:username])
            debug(password)
            deploy_private_key(state[:hostname], ssh)
          else
            info("No keypair specified (or file not found) nor is this a password enabled template. You will have to manually copy your SSH public key to #{state[:hostname]} to use this Kitchen.")
          end
        end
      end

      def destroy(state)
        return if state[:server_id].nil?

        server = compute.servers.get(state[:server_id])
        server.destroy unless server.nil?
        info("CloudStack instance <#{state[:server_id]}> destroyed.")
        state.delete(:server_id)
        state.delete(:hostname)
      end

      def tcp_test_ssh(hostname)
        # Ripped unceremoniously from knife-cloudstack-fog as I was having issues with the wait_for_sshd() function.
        print(". ")
        tcp_socket = TCPSocket.new(hostname, 22)
        readable = IO.select([tcp_socket], nil, nil, 5)
        if readable
          debug("\nsshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}\n")
          true
        else
          false
        end

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
      ensure
        tcp_socket && tcp_socket.close
      end

      def deploy_private_key(hostname, ssh)
        debug("Deploying private key to #{hostname} using connection #{ssh}")
        tcp_test_ssh(hostname)
        sync_time = 45
        if (config[:cloudstack_sync_time])
          sync_time = config[:cloudstack_sync_time]
        end
        debug("Sync time is #{sync_time}")
        if !(config[:public_key_path].nil?)
          pub_key = open(config[:public_key_path]).read
          # Wait a few moments for the OS to run the cloud-setup-password scripts
          sleep(sync_time)
          ssh.run([
                      %{mkdir .ssh},
                      %{echo "#{pub_key}" >> ~/.ssh/authorized_keys}
                  ])

        end
      end
    end
  end
end
