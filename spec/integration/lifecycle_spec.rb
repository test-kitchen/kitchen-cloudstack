require "spec_helper"
require "kitchen/driver/cloudstack"
require "kitchen/transport/dummy"
require "kitchen/provisioner/dummy"
require "kitchen/verifier/dummy"
require "json"
require "net/http"
require "tmpdir"

# Exercises the whole stack -- Test Kitchen, the driver, and cloudstack_client
# -- with only the HTTP boundary stubbed, so the real request signing, response
# parsing and plugin wiring all run.
RSpec.describe "CloudStack instance lifecycle" do
  # Stands in for Net::HTTP, answering each request from #api_response.
  class StubHttp
    attr_accessor :use_ssl, :verify_mode, :read_timeout

    def initialize(&responder)
      @responder = responder
    end

    def request(req)
      body = @responder.call(req.uri || URI.parse(req.path))
      response = Net::HTTPOK.new("1.1", "200", "")
      response.instance_variable_set(:@body, body)
      response.instance_variable_set(:@read, true)
      response
    end
  end

  around do |example|
    original = Net::HTTP.method(:new)
    stub = StubHttp.new { |uri| api_response(uri) }
    Net::HTTP.define_singleton_method(:new) { |*_args| stub }
    example.run
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  let(:vm) do
    {
      "id" => "vm-e2e",
      "passwordenabled" => true,
      "password" => "s3cret",
      "nic" => [{ "ipaddress" => "10.9.9.9" }],
    }
  end

  # Answers the handful of CloudStack commands this lifecycle issues.
  def api_response(uri)
    command = URI.decode_www_form(uri.query.to_s).to_h["command"]
    body =
      case command
      when "deployVirtualMachine"
        { "deployvirtualmachineresponse" => { "id" => "vm-e2e", "jobid" => "job-e2e" } }
      when "queryAsyncJobResult"
        { "queryasyncjobresultresponse" => {
          "jobstatus" => 1, "jobresult" => { "virtualmachine" => vm },
        } }
      when "listVirtualMachines"
        { "listvirtualmachinesresponse" => {
          "count" => 1,
          "virtualmachine" => [{ "id" => "vm-e2e", "state" => "Running" }],
        } }
      when "destroyVirtualMachine"
        { "destroyvirtualmachineresponse" => { "jobid" => "job-destroy" } }
      else
        {}
      end

    JSON.generate(body)
  end

  let(:driver) do
    Kitchen::Driver::Cloudstack.new(
      cloudstack_api_url: "https://cs.example.com/client/api",
      cloudstack_api_key: "key",
      cloudstack_secret_key: "secret",
      cloudstack_template_id: "t",
      cloudstack_serviceoffering_id: "o",
      cloudstack_zone_id: "z"
    )
  end

  before do
    state_file = Kitchen::StateFile.new(Dir.mktmpdir, "default-ubuntu")
    Kitchen::Instance.new(
      driver: driver,
      suite: Kitchen::Suite.new(name: "default"),
      platform: Kitchen::Platform.new(name: "ubuntu"),
      provisioner: Kitchen::Provisioner::Dummy.new,
      transport: Kitchen::Transport::Dummy.new,
      verifier: Kitchen::Verifier::Dummy.new,
      lifecycle_hooks: Kitchen::LifecycleHooks.new({}, state_file),
      state_file: state_file,
      logger: Kitchen::Logger.new(stdout: StringIO.new)
    )
  end

  it "creates an instance and records how to reach it" do
    state = {}
    driver.create(state)

    expect(state[:server_id]).to eq("vm-e2e")
    expect(state[:hostname]).to eq("10.9.9.9")
    expect(state[:password]).to eq("s3cret")
  end

  it "reports the created instance as live" do
    state = {}
    driver.create(state)

    expect(driver.status(state)).to include(live: true, state: "Running", resource_id: "vm-e2e")
  end

  it "leaves no instance details behind after destroy" do
    state = {}
    driver.create(state)
    driver.destroy(state)

    expect(state).to be_empty
  end
end
