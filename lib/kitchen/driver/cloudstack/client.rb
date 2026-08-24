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
require "cloudstack_client"

module Kitchen
  module Driver
    class Cloudstack < Kitchen::Driver::Base
      # Wraps the CloudStack API connection and the asynchronous job protocol.
      #
      # Almost every CloudStack call that changes something returns a job id
      # rather than a result, so callers use {#run_job} to turn that job id
      # into the eventual result, or into an ActionFailed.
      #
      # cloudstack_client can wait for those jobs itself, but doing so hands
      # back only the finished job result -- the caller never sees the id of
      # the resource being built. The driver records that id in instance state
      # before waiting, so that an interrupted +kitchen create+ still leaves
      # behind enough state to destroy what it started. Every asynchronous
      # call is therefore made with +sync: true+, which returns CloudStack's
      # immediate response, and the waiting happens here instead.
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

        # Options passed to every asynchronous API call, asking for
        # CloudStack's immediate response rather than cloudstack_client's own
        # job polling. See the class documentation for why.
        SYNC = { sync: true }.freeze

        # @param config [Hash] the driver configuration
        # @param api [CloudstackClient::Client, nil] an existing connection,
        #   for tests
        # @param sleeper [#call, nil] receives a number of seconds to wait,
        #   for tests that must not actually sleep
        def initialize(config, api: nil, sleeper: nil)
          @config = config
          @api = api
          @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        end

        # The CloudStack connection, built from the configured endpoint.
        #
        # Certificate verification is on unless +disable_ssl_validation+ asks
        # for it to be off, and unlike the fog connection this replaced, that
        # choice is scoped to this connection rather than set process-wide.
        #
        # @return [CloudstackClient::Client] a CloudStack API connection
        def api
          @api ||= CloudstackClient::Client.new(
            config[:cloudstack_api_url],
            config[:cloudstack_api_key],
            config[:cloudstack_secret_key],
            quiet: true,
            ssl_verify: !config[:disable_ssl_validation]
          )
        end

        # Waits for an asynchronous CloudStack job to finish.
        #
        # @param jobid [String] the job id returned by the triggering call
        # @return [Hash] the job's "jobresult" payload
        # @raise [Kitchen::ActionFailed] if the job fails or does not finish
        def run_job(jobid)
          elapsed = 0

          loop do
            response = api.query_async_job_result("jobid" => jobid)

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
