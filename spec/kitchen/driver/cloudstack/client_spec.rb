require "spec_helper"
require "kitchen/driver/cloudstack/client"

RSpec.describe Kitchen::Driver::Cloudstack::Client do
  # Records the arguments it is called with and replays queued responses.
  class FakeApi
    attr_reader :job_queries

    def initialize(responses)
      @responses = responses
      @job_queries = []
    end

    def query_async_job_result(args)
      @job_queries << args
      @responses.shift || raise("FakeApi ran out of responses")
    end
  end

  # cloudstack_client strips the response envelope, so a job query comes back
  # as the job payload itself rather than wrapped in a named key.
  def job_response(status, result = {})
    { "jobstatus" => status, "jobresult" => result }
  end

  def client_for(responses, config = {})
    described_class.new(
      { cloudstack_job_poll_interval: 1, cloudstack_job_timeout: 5 }.merge(config),
      api: FakeApi.new(responses),
      sleeper: ->(_seconds) {}
    )
  end

  describe "#run_job" do
    it "returns the job result once the job succeeds" do
      client = client_for([job_response(1, { "virtualmachine" => { "id" => "vm-1" } })])

      expect(client.run_job("job-1")).to eq({ "virtualmachine" => { "id" => "vm-1" } })
    end

    it "keeps polling while the job is still running" do
      client = client_for([job_response(0), job_response(0), job_response(1, { "ok" => true })])

      expect(client.run_job("job-1")).to eq({ "ok" => true })
    end

    it "raises ActionFailed with CloudStack's error text when the job fails" do
      client = client_for([job_response(2, { "errortext" => "Insufficient capacity" })])

      expect { client.run_job("job-1") }
        .to raise_error(Kitchen::ActionFailed, /Insufficient capacity/)
    end

    it "raises ActionFailed when the job never leaves the running state" do
      client = client_for([job_response(0)] * 50, cloudstack_job_timeout: 3)

      expect { client.run_job("job-1") }.to raise_error(Kitchen::ActionFailed, /timed out/i)
    end

    it "queries by job id" do
      api = FakeApi.new([job_response(1)])
      client = described_class.new(
        { cloudstack_job_poll_interval: 1, cloudstack_job_timeout: 5 },
        api: api, sleeper: ->(_s) {}
      )

      client.run_job("job-1")

      expect(api.job_queries).to eq([{ "jobid" => "job-1" }])
    end
  end

  describe "#api" do
    let(:config) do
      {
        cloudstack_api_url: "https://cs.example.com:8443/client/api",
        cloudstack_api_key: "key",
        cloudstack_secret_key: "secret",
      }
    end

    it "builds a cloudstack_client connection from the CloudStack API url" do
      expect(CloudstackClient::Client).to receive(:new).with(
        "https://cs.example.com:8443/client/api",
        "key",
        "secret",
        hash_including(quiet: true)
      )

      described_class.new(config).api
    end

    it "verifies the server certificate by default" do
      expect(CloudstackClient::Client).to receive(:new).with(
        anything, anything, anything, hash_including(ssl_verify: true)
      )

      described_class.new(config).api
    end

    it "stops verifying the server certificate when disable_ssl_validation is set" do
      expect(CloudstackClient::Client).to receive(:new).with(
        anything, anything, anything, hash_including(ssl_verify: false)
      )

      described_class.new(config.merge(disable_ssl_validation: true)).api
    end

    it "builds the connection only once" do
      expect(CloudstackClient::Client).to receive(:new).once.and_return(double)

      client = described_class.new(config)
      client.api
      client.api
    end
  end
end
