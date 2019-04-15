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
require 'base64'

module Kitchen
  module Driver
    # Cloudstack driver for Kitchen.
    #
    # @author Jeff Moody <fifthecho@gmail.com>
    class Cloudstack < Kitchen::Driver::SSHBase
      default_config :name,             nil
      default_config :username,         'root'
      default_config :port,             '22'
      default_config :password,         nil
      default_config :cloudstack_create_firewall_rule, false

      def compute
        cloudstack_uri =  URI.parse(config[:cloudstack_api_url])
        connection = Fog::Compute.new(
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

      def create_server
        options = {}

        config[:server_name] ||= generate_name(instance.name)

        options['displayname'] = config[:server_name]
        options['networkids']  = config[:cloudstack_network_id]
        options['securitygroupids'] = config[:cloudstack_security_group_id]
        options['keypair'] = config[:cloudstack_ssh_keypair_name]
        options['diskofferingid'] = config[:cloudstack_diskoffering_id]
        options['name'] = config[:host_name]
        options[:userdata] = convert_userdata(config[:cloudstack_userdata]) if config[:cloudstack_userdata]

        options = sanitize(options)

        options[:templateid] = config[:cloudstack_template_id]
        options[:serviceofferingid] = config[:cloudstack_serviceoffering_id]
        options[:zoneid] = config[:cloudstack_zone_id]

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
        start_jobid = {
          'jobid' => server['deployvirtualmachineresponse'].fetch('jobid')
        }
        info("CloudStack instance <#{state[:server_id]}> created.")
        debug("Job ID #{start_jobid}")
        # Cloning the original job id hash because running the
        # query_async_job_result updates the hash to include
        # more than just the job id (which I could work around, but I'm lazy).
        jobid = start_jobid.clone

        server_start = compute.query_async_job_result(jobid)
        # jobstatus of zero is a running job
        while server_start['queryasyncjobresultresponse'].fetch('jobstatus').to_i == 0
          debug("Job status: #{server_start}")
          print ". "
          sleep(10)
          debug("Running Job ID #{jobid}")
          debug("Start Job ID #{start_jobid}")
          # We have to reclone on each iteration, as the hash keeps getting updated.
          jobid = start_jobid.clone
          server_start = compute.query_async_job_result(jobid)
        end
        debug("Server_Start: #{server_start} \n")

        # jobstatus of 2 is an error response
        if server_start['queryasyncjobresultresponse'].fetch('jobstatus').to_i == 2
          errortext = server_start['queryasyncjobresultresponse']
            .fetch('jobresult')
            .fetch('errortext')

          error("ERROR! Job failed with #{errortext}")

          raise ActionFailed, "Could not create server #{errortext}"
        end

        # jobstatus of 1 is a succesfully completed async job
        if server_start['queryasyncjobresultresponse'].fetch('jobstatus').to_i == 1
          server_info = server_start['queryasyncjobresultresponse']['jobresult']['virtualmachine']
          debug(server_info)
          print "(server ready)"

          keypair = nil
          if config[:keypair_search_directory] and File.exist?(
            "#{config[:keypair_search_directory]}/#{config[:cloudstack_ssh_keypair_name]}.pem"
          )
            keypair = "#{config[:keypair_search_directory]}/#{config[:cloudstack_ssh_keypair_name]}.pem"
            debug("Keypair being used is #{keypair}")
          elsif File.exist?("./#{config[:cloudstack_ssh_keypair_name]}.pem")
            keypair = "./#{config[:cloudstack_ssh_keypair_name]}.pem"
            debug("Keypair being used is #{keypair}")
          elsif File.exist?("#{ENV["HOME"]}/#{config[:cloudstack_ssh_keypair_name]}.pem")
            keypair = "#{ENV["HOME"]}/#{config[:cloudstack_ssh_keypair_name]}.pem"
            debug("Keypair being used is #{keypair}")
          elsif File.exist?("#{ENV["HOME"]}/.ssh/#{config[:cloudstack_ssh_keypair_name]}.pem")
            keypair = "#{ENV["HOME"]}/.ssh/#{config[:cloudstack_ssh_keypair_name]}.pem"
            debug("Keypair being used is #{keypair}")
          elsif (!config[:cloudstack_ssh_keypair_name].nil?)
            info("Keypair specified but not found. Using password if enabled.")
          end

          if config[:associate_public_ip]
            info("Associating public ip...")
            state[:hostname] = associate_public_ip(state, server_info)
            info("Creating port forward...")
            create_port_forward(state, server_info['id'])
          else
            state[:hostname] = default_public_ip(server_info) unless config[:associate_public_ip]
          end

          if keypair
            debug("Using keypair: #{keypair}")
            info("SSH for #{state[:hostname]} with keypair #{config[:cloudstack_ssh_keypair_name]}.")
            ssh_key = File.read(keypair)
            if ssh_key.split[0] == "ssh-rsa" or ssh_key.split[0] == "ssh-dsa"
              error("SSH key #{keypair} is not a Private Key. Please modify your .kitchen.yml")
            end

            wait_for_sshd(state[:hostname], config[:username], {:keys => keypair})
            debug("SSH connectivity validated with keypair.")

            ssh = Fog::SSH.new(state[:hostname], config[:username], {:keys => keypair})
            debug("Connecting to : #{state[:hostname]} as #{config[:username]} using keypair #{keypair}.")
          elsif server_info.fetch('passwordenabled')
            password = server_info.fetch('password')
            config[:password] = password
            # Print out IP and password so you can record it if you want.
            info("Password for #{config[:username]} at #{state[:hostname]} is #{password}")

            wait_for_sshd(state[:hostname], config[:username], {:password => password})
            debug("SSH connectivity validated with cloudstack-set password.")

            ssh = Fog::SSH.new(state[:hostname], config[:username], {:password => password})
            debug("Connecting to : #{state[:hostname]} as #{config[:username]} using password #{password}.")
          elsif config[:password]
            info("Connecting with user #{config[:username]} with password #{config[:password]}")

            wait_for_sshd(state[:hostname], config[:username], {:password => config[:password]})
            debug("SSH connectivity validated with fixed password.")

            ssh = Fog::SSH.new(state[:hostname], config[:username], {:password => config[:password]})
          else
            info("No keypair specified (or file not found) nor is this a password enabled template. You will have to manually copy your SSH public key to #{state[:hostname]} to use this Kitchen.")
          end

          validate_ssh_connectivity(ssh)

          deploy_private_key(ssh)
        end
      end

      def destroy(state)
        return unless state[:server_id]
        if config[:associate_public_ip]
          delete_port_forward(state)
          release_public_ip(state)
        end
        debug("Destroying #{state[:server_id]}")
        server = compute.servers.get(state[:server_id])
        expunge =
          if !!config[:cloudstack_expunge] == config[:cloudstack_expunge]
            config[:cloudstack_expunge]
          else
            false
          end
        if server
          compute.destroy_virtual_machine(
            {
              'id' => state[:server_id],
              'expunge' => expunge
            }
          )
        end
        info("CloudStack instance <#{state[:server_id]}> destroyed.")
        state.delete(:server_id)
        state.delete(:hostname)
      end

      def validate_ssh_connectivity(ssh)
      rescue Errno::ETIMEDOUT
        debug("SSH connection timed out. Retrying.")
        sleep 2
        false
      rescue Errno::EPERM
        debug("SSH connection returned error. Retrying.")
        false
      rescue Errno::ECONNREFUSED
        debug("SSH connection returned connection refused. Retrying.")
        sleep 2
        false
      rescue Errno::EHOSTUNREACH
        debug("SSH connection returned host unreachable. Retrying.")
        sleep 2
        false
      rescue Errno::ENETUNREACH
        debug("SSH connection returned network unreachable. Retrying.")
        sleep 30
        false
      rescue Net::SSH::Disconnect
        debug("SSH connection has been disconnected. Retrying.")
        sleep 15
        false
      rescue Net::SSH::AuthenticationFailed
        debug("SSH authentication has failed. Password or Keys may not be in place yet. Retrying.")
        sleep 15
        false
      ensure
        sync_time = 0
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
          if pieces[2] && pieces[2].length > 24
            pieces[2] = pieces[2][0..-2]
          elsif pieces[1] && pieces[1].length > 16
            pieces[1] = pieces[1][0..-2]
          elsif pieces[0] && pieces[0].length > 16
            pieces[0] = pieces[0][0..-2]
          end
        end
        pieces.join sep
      end

      private

      def sanitize(options)
        options.reject { |k, v| v.nil? }
      end

      def convert_userdata(user_data)
        if user_data.match /^(?:[A-Za-z0-9+\/]{4}\n?)*(?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=)?$/
          user_data
        else
          Base64.encode64(user_data)
        end
      end

      def associate_public_ip(state, server_info)
        options = {
          'zoneid' => config[:cloudstack_zone_id],
          'vpcid' => get_vpc_id,
          'networkid' => config[:cloudstack_network_id]
        }
        res = compute.associate_ip_address(options)
        job_status = compute.query_async_job_result(res['associateipaddressresponse']['jobid'])
        if job_status['queryasyncjobresultresponse'].fetch('jobstatus').to_i == 1
          save_ipaddress_id(state, job_status)
          ip_address = get_public_ip(res['associateipaddressresponse']['id'])
        else
          error(job_status['queryasyncjobresultresponse'].fetch('jobresult'))
        end

        if config[:cloudstack_create_firewall_rule]
          info("Creating firewall rule for SSH")
          # create firewallrule projectid=<project> cidrlist=<0.0.0.0/0 or your source> protocol=tcp startport=0 endport=65535 (or you can restrict to 22 if you want) ipaddressid=<public ip address id>
          options = {
            'projectid' => config[:cloudstack_project_id],
            'cidrlist' => '0.0.0.0/0',
            'protocol' => 'tcp',
            'startport' => 22,
            'endport' => 22,
            'ipaddressid' => state[:ipaddressid]
          }
          res = compute.create_firewall_rule(options)
          status = 0
          timeout = 10
          while status == 0
            job_status = compute.query_async_job_result(res['createfirewallruleresponse']['jobid'])
            status = job_status['queryasyncjobresultresponse'].fetch('jobstatus').to_i
            timeout -= 1
            error("Failed to create firewall rule by timeout") if timeout == 0
            sleep 1
          end

          if job_status['queryasyncjobresultresponse'].fetch('jobstatus').to_i == 1
            save_firewall_rule_id(state, job_status)
            info('Firewall rule successfully created')
          else
            error(job_status['queryasyncjobresultresponse'])
          end
        end

        ip_address
      end

      def create_port_forward(state, virtualmachineid)
        options = {
          'ipaddressid' => state[:ipaddressid],
          'privateport' => 22,
          'protocol' => "TCP",
          'publicport' => 22,
          'virtualmachineid' => virtualmachineid,
          'networkid' => config[:cloudstack_network_id],
          'openfirewall' => false
        }
        res = compute.create_port_forwarding_rule(options)
        job_status = compute.query_async_job_result(res['createportforwardingruleresponse']['jobid'])
        unless job_status['queryasyncjobresultresponse'].fetch('jobstatus').to_i == 0
          error("Error creating port forwarding rules")
        end
        save_forwarding_port_rule_id(state, res['createportforwardingruleresponse']['id'])
      end

      def release_public_ip(state)
        info("Disassociating public ip...")
        begin
          res = compute.disassociate_ip_address(state[:ipaddressid])
        rescue Fog::Compute::Cloudstack::BadRequest => e
          error(e) unless e.to_s.match?(/does not exist/)
        else
          job_status = compute.query_async_job_result(res['disassociateipaddressresponse']['jobid'])
          unless job_status['queryasyncjobresultresponse'].fetch('jobstatus').to_i == 0
            error("Error disassociating public ip")
          end
        end

        if state[:firewall_rule_id]
          info("Removing firewall rule '#{state[:firewall_rule_id]}'")

          begin
            res = compute.delete_firewall_rule(state[:firewall_rule_id])
          rescue Fog::Compute::Cloudstack::BadRequest => e
            error(e) unless e.to_s.match?(/does not exist/)
          else
            job_status = compute.query_async_job_result(res['deletefirewallruleresponse']['jobid'])
            unless job_status['queryasyncjobresultresponse'].fetch('jobstatus').to_i == 0
              error("Error removing firewall rule '#{state[:firewall_rule_id]}'")
            end
          end
        end
      end

      def delete_port_forward(state)
        info("Deleting port forwarding rules...")
        begin
          res = compute.delete_port_forwarding_rule(state[:forwardingruleid])
        rescue Fog::Compute::Cloudstack::BadRequest => e
          error(e) unless e.to_s.match?(/does not exist/)
        else
          job_status = compute.query_async_job_result(res['deleteportforwardingruleresponse']['jobid'])
          unless job_status['queryasyncjobresultresponse'].fetch('jobstatus').to_i == 0
            error("Error deleting port forwarding rules")
          end
        end
      end

      def get_vpc_id
        compute.list_networks['listnetworksresponse']['network']
          .select{|e| e['id'] == config[:cloudstack_network_id]}.first['vpcid']
      end

      def get_public_ip(public_ip_uuid)
        compute.list_public_ip_addresses['listpublicipaddressesresponse']['publicipaddress']
          .select{|e| e['id'] == public_ip_uuid}
          .first['ipaddress']
      end

      def save_ipaddress_id(state, job_status)
        state[:ipaddressid] = job_status['queryasyncjobresultresponse']
                                .fetch('jobresult')
                                .fetch('ipaddress')
                                .fetch('id')
      end

      def save_firewall_rule_id(state, job_status)
        state[:firewall_rule_id] = job_status['queryasyncjobresultresponse']
                                .fetch('jobresult')
                                .fetch('firewallrule')
                                .fetch('id')
      end

      def save_forwarding_port_rule_id(state, uuid)
        state[:forwardingruleid] = uuid
      end

      def default_public_ip(server_info)
        config[:cloudstack_vm_public_ip] || server_info.fetch('nic').first.fetch('ipaddress')
      end
    end
  end
end
