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
        if (!config[:cloudstack_security_group_id].nil?)
          options['securitygroupids'] = config[:cloudstack_security_group_id]
        end
        if (!config[:cloudstack_network_id].nil?)
          options['networkids'] = config[:cloudstack_security_group_id]
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
        password = ''
        if (!config[:cloudstack_ssh_keypair_name].nil?)
          keypair = config[:cloudstack_ssh_keypair_name]
        end
        server = create_server
        debug(server)
        state[:server_id] = server['deployvirtualmachineresponse'].fetch('id')
        jobid = server['deployvirtualmachineresponse'].fetch('jobid')
        info("CloudStack instance <#{state[:server_id]}> created.")
        debug("Job ID #{jobid}")
        server_start = compute.query_async_job_result('jobid'=>jobid)
        while server_start['queryasyncjobresultresponse'].fetch('jobstatus') == 0
          print "."
          sleep(10)
          server_start = compute.query_async_job_result('jobid'=>jobid)
          debug("Server_Start: #{server_start} \n")
        end
        if server_start['queryasyncjobresultresponse'].fetch('jobstatus') == 2
          errortext = server_start['queryasyncjobresultresponse'].fetch('jobresult').fetch('errortext')
          error("ERROR! Job failed with #{errortext}")
        end

        if server_start['queryasyncjobresultresponse'].fetch('jobstatus') == 1
          server_info = server_start['queryasyncjobresultresponse']['jobresult']['virtualmachine']
          debug(server_info)
          puts "\n(server ready)"
          if (server_info.fetch('passwordenabled') == true)
              password = server_info.fetch('password')
              state[:hostname] = server_info.fetch('nic').first.fetch('ipaddress')
              info("Password for #{config[:username]} at #{state[:hostname]} is #{password}")
              ssh = Fog::SSH.new(state[:hostname], config[:username], {:password => password})
              debug(state[:hostname])
              debug(config[:username])
              debug(password)
              tcp_test_ssh(state[:hostname])
# Installing SSH keys is consistently failing. Not sure why.
               if !(config[:public_key_path].nil?)
                pub_key = open(config[:public_key_path]).read
                # Wait a few moments for the OS to run the cloud-setup-sshkey/password scripts
                sleep(30)
                ssh.run([
                          %{mkdir .ssh},
                          %{echo "#{pub_key}" >> ~/.ssh/authorized_keys}
                      ])
              end
              info("(ssh ready)")
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
        print(".")
        tcp_socket = TCPSocket.new(hostname, 22)
        readable = IO.select([tcp_socket], nil, nil, 5)
        if readable
          debug("\nsshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}\n")
          yield
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

    end
  end
end
