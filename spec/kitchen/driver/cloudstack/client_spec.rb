require "spec_helper"
require "kitchen/driver/cloudstack/client"

RSpec.describe Kitchen::Driver::Cloudstack::Client do
  # Records the arguments it is called with and replays queued responses.
  class FakeCompute
    attr_reader :job_queries

    def initialize(responses)
      @responses = responses
      @job_queries = []
    end

    def query_async_job_result(jobid)
      @job_queries << jobid
      @responses.shift || raise("FakeCompute ran out of responses")
    end
  end

  def job_response(status, result = {})
    { "queryasyncjobresultresponse" => { "jobstatus" => status, "jobresult" => result } }
  end

  def client_for(responses, config = {})
    described_class.new(
      { cloudstack_job_poll_interval: 1, cloudstack_job_timeout: 5 }.merge(config),
      compute: FakeCompute.new(responses),
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

    it "queries with the bare job id so fog cannot mutate caller state" do
      compute = FakeCompute.new([job_response(1)])
      client = described_class.new(
        { cloudstack_job_poll_interval: 1, cloudstack_job_timeout: 5 },
        compute: compute, sleeper: ->(_s) {}
      )

      client.run_job("job-1")

      expect(compute.job_queries).to eq(["job-1"])
    end
  end

  describe "#run_response_job" do
    it "takes the job id out of the response envelope and waits for that job" do
      compute = FakeCompute.new([job_response(1, { "done" => true })])
      client = described_class.new(
        { cloudstack_job_poll_interval: 1, cloudstack_job_timeout: 5 },
        compute: compute, sleeper: ->(_s) {}
      )

      result = client.run_response_job(
        { "createfirewallruleresponse" => { "jobid" => "job-9" } },
        "createfirewallruleresponse"
      )

      expect(result).to eq({ "done" => true })
      expect(compute.job_queries).to eq(["job-9"])
    end
  end

  describe "#compute" do
    it "builds a fog connection from the CloudStack API url" do
      client = described_class.new({
        cloudstack_api_url: "https://cs.example.com:8443/client/api",
        cloudstack_api_key: "key",
        cloudstack_secret_key: "secret",
      })

      expect(Fog::Compute).to receive(:new).with(
        hash_including(
          provider: :cloudstack,
          cloudstack_host: "cs.example.com",
          cloudstack_port: 8443,
          cloudstack_path: "/client/api",
          cloudstack_scheme: "https",
          cloudstack_api_key: "key",
          cloudstack_secret_access_key: "secret"
        )
      )

      client.compute
    end
  end
end
