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
require "kitchen/errors"
require "fog/cloudstack"
require "uri" unless defined?(URI)

module Kitchen
  module Driver
    class Cloudstack < Kitchen::Driver::Base
      # Wraps the CloudStack API connection and the asynchronous job protocol.
      #
      # Almost every CloudStack call that changes something returns a job id
      # rather than a result, so callers use {#run_job} to turn that job id
      # into the eventual result, or into an ActionFailed.
      class Client
        # Value CloudStack reports in an async job's "jobstatus" field while
        # the job is still running.
        JOB_RUNNING = 0

        # Value CloudStack reports in "jobstatus" once the job has succeeded.
        JOB_SUCCEEDED = 1

        # Value CloudStack reports in "jobstatus" once the job has failed.
        JOB_FAILED = 2

        # Seconds between polls of an async job, when +cloudstack_job_poll_interval+
        # is not configured.
        DEFAULT_POLL_INTERVAL = 10

        # Seconds to wait for an async job, when +cloudstack_job_timeout+ is
        # not configured.
        DEFAULT_TIMEOUT = 600

        # @param config [Hash] the driver configuration
        # @param compute [Fog::Compute, nil] an existing connection, for tests
        # @param sleeper [#call, nil] receives a number of seconds to wait,
        #   for tests that must not actually sleep
        def initialize(config, compute: nil, sleeper: nil)
          @config = config
          @compute = compute
          @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        end

        # The fog CloudStack connection, built from the configured endpoint.
        #
        # The API URL is split into scheme, host, port, and path because fog
        # wants them separately rather than as one URL.
        #
        # @return [Fog::Compute] a CloudStack compute connection
        def compute
          @compute ||= begin
            uri = URI.parse(config[:cloudstack_api_url])
            Fog::Compute.new(
              provider: :cloudstack,
              cloudstack_api_key: config[:cloudstack_api_key],
              cloudstack_secret_access_key: config[:cloudstack_secret_key],
              cloudstack_host: uri.host,
              cloudstack_port: uri.port,
              cloudstack_path: uri.path,
              cloudstack_project_id: config[:cloudstack_project_id],
              cloudstack_scheme: uri.scheme
            )
          end
        end

        # Waits for an asynchronous CloudStack job to finish.
        #
        # @param jobid [String] the job id returned by the triggering call
        # @return [Hash] the job's "jobresult" payload
        # @raise [Kitchen::ActionFailed] if the job fails or does not finish
        def run_job(jobid)
          elapsed = 0

          loop do
            response = compute.query_async_job_result(jobid)["queryasyncjobresultresponse"]

            case response.fetch("jobstatus").to_i
            when JOB_SUCCEEDED
              return response["jobresult"]
            when JOB_FAILED
              raise ActionFailed, "CloudStack job #{jobid} failed: #{job_error(response)}"
            end

            if elapsed >= timeout
              raise ActionFailed,
                "CloudStack job #{jobid} timed out after #{timeout} seconds"
            end

            sleeper.call(poll_interval)
            elapsed += poll_interval
          end
        end

        # Runs a request that returns an async job id, and waits for it.
        #
        # @param response [Hash] the raw response from a fog request
        # @param key [String] the response envelope key holding the job id
        # @return [Hash] the job's "jobresult" payload
        def run_response_job(response, key)
          run_job(response.fetch(key).fetch("jobid"))
        end

        private

        attr_reader :config, :sleeper

        # @return [Integer] seconds between polls of a running job
        def poll_interval
          config[:cloudstack_job_poll_interval] || DEFAULT_POLL_INTERVAL
        end

        # @return [Integer] seconds to wait before giving up on a job
        def timeout
          config[:cloudstack_job_timeout] || DEFAULT_TIMEOUT
        end

        # CloudStack reports failures as an "errortext" inside the job result,
        # but falls back to the whole payload when the shape is unexpected.
        #
        # @param response [Hash] the async job payload
        # @return [String] a message describing the failure
        def job_error(response)
          result = response["jobresult"]
          return response.inspect unless result.is_a?(Hash)

          result["errortext"] || result.inspect
        end
      end
    end
  end
end
