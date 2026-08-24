require "spec_helper"
require "kitchen/driver/cloudstack"
require "kitchen/transport/ssh"
require "kitchen/transport/winrm"
require "kitchen/provisioner/dummy"
require "kitchen/verifier/dummy"
require "logger"

RSpec.describe Kitchen::Driver::Cloudstack do
  # Stands in for the CloudStack API, recording what the driver asked for.
  class DriverFakeClient
    attr_reader :api, :calls

    def initialize(vm_info:, vm_state: "Running")
      @vm_info = vm_info
      @vm_state = vm_state
      @calls = []
      @api = Recorder.new(self)
    end

    # cloudstack_client strips the response envelope, and every asynchronous
    # call is made with sync: true, so each answers with CloudStack's
    # immediate response rather than the finished job result.
    class Recorder
      def initialize(owner) = @owner = owner

      def method_missing(name, *args)
        @owner.calls << [name, args.first]
        case name
        when :deploy_virtual_machine
          { "id" => "vm-1", "jobid" => "job-1" }
        when :list_virtual_machines
          [{ "id" => "vm-1", "state" => @owner.vm_state }]
        when :associate_ip_address
          { "id" => "ip-uuid", "jobid" => "job-ip" }
        else
          { "id" => "#{name}-id", "jobid" => "#{name}-job" }
        end
      end

      def respond_to_missing?(_n, _p = false) = true
    end

    attr_reader :vm_state

    def run_job(jobid)
      @calls << [:run_job, jobid]
      case jobid
      when "job-ip"
        { "ipaddress" => { "id" => "ip-uuid", "ipaddress" => "203.0.113.9" } }
      when "create_firewall_rule-job"
        { "firewallrule" => { "id" => "fw-1" } }
      else
        { "virtualmachine" => @vm_info }
      end
    end

    def called?(name) = calls.any? { |c| c.first == name }
    def call_named(name) = calls.find { |c| c.first == name }&.last
  end

  let(:vm_info) do
    { "id" => "vm-1", "nic" => [{ "ipaddress" => "10.0.0.5" }], "passwordenabled" => false }
  end

  let(:client) { DriverFakeClient.new(vm_info: vm_info) }
  let(:transport) { Kitchen::Transport::Ssh.new }
  let(:connection) { instance_double(Kitchen::Transport::Ssh::Connection, wait_until_ready: true) }

  let(:base_config) do
    {
      cloudstack_api_url: "https://cs.example.com/client/api",
      cloudstack_template_id: "tmpl-1",
      cloudstack_serviceoffering_id: "offer-1",
      cloudstack_zone_id: "zone-1",
      cloudstack_job_poll_interval: 0,
    }
  end

  def build_driver(config = {})
    driver = described_class.new(base_config.merge(config))
    allow(driver).to receive(:client).and_return(client)

    state_file = Kitchen::StateFile.new(Dir.mktmpdir, "default-ubuntu")
    Kitchen::Instance.new(
      driver: driver,
      suite: Kitchen::Suite.new(name: "default"),
      platform: Kitchen::Platform.new(name: "ubuntu"),
      provisioner: Kitchen::Provisioner::Dummy.new,
      transport: transport,
      verifier: Kitchen::Verifier::Dummy.new,
      lifecycle_hooks: Kitchen::LifecycleHooks.new({}, state_file),
      state_file: state_file,
      logger: Kitchen::Logger.new(stdout: StringIO.new)
    )
    allow(transport).to receive(:connection).and_return(connection)
    driver
  end

  describe "#create" do
    it "records the created instance id in state" do
      state = {}
      build_driver.create(state)

      expect(state[:server_id]).to eq("vm-1")
    end

    it "uses the instance's own address when no public IP is requested" do
      state = {}
      build_driver.create(state)

      expect(state[:hostname]).to eq("10.0.0.5")
    end

    it "prefers an explicitly configured public address" do
      state = {}
      build_driver(cloudstack_vm_public_ip: "203.0.113.1").create(state)

      expect(state[:hostname]).to eq("203.0.113.1")
    end

    it "waits for the configured transport to become ready" do
      expect(connection).to receive(:wait_until_ready)

      build_driver.create({})
    end

    it "passes the CloudStack generated password to the transport via state" do
      vm_info["passwordenabled"] = true
      vm_info["password"] = "generated-pw"
      state = {}
      build_driver.create(state)

      expect(state[:password]).to eq("generated-pw")
    end

    it "does not override transport configured credentials by default" do
      state = {}
      build_driver.create(state)

      expect(state).not_to have_key(:username)
      expect(state).not_to have_key(:port)
    end

    it "raises rather than continuing when the deploy job fails" do
      driver = build_driver
      allow(client).to receive(:run_job).and_raise(Kitchen::ActionFailed, "Insufficient capacity")

      expect { driver.create({}) }.to raise_error(Kitchen::ActionFailed, /Insufficient capacity/)
    end
  end

  describe "#destroy" do
    it "destroys the CloudStack instance" do
      build_driver.destroy(server_id: "vm-1")

      expect(client.call_named(:destroy_virtual_machine)["id"]).to eq("vm-1")
    end

    it "honours the expunge setting" do
      build_driver(cloudstack_expunge: true).destroy(server_id: "vm-1")

      expect(client.call_named(:destroy_virtual_machine)["expunge"]).to eq("true")
    end

    # cloudstack_client drops any argument whose value is falsey, so a
    # boolean false never reaches CloudStack at all.
    it "sends a disabled expunge setting as a string so it is not dropped" do
      build_driver(cloudstack_expunge: false).destroy(server_id: "vm-1")

      expect(client.call_named(:destroy_virtual_machine)["expunge"]).to eq("false")
    end

    it "looks the instance up inside a configured project" do
      build_driver(cloudstack_project_id: "proj-1").status(server_id: "vm-1")

      expect(client.call_named(:list_virtual_machines)["projectid"]).to eq("proj-1")
    end

    it "clears the instance details from state" do
      state = { server_id: "vm-1", hostname: "10.0.0.5" }
      build_driver.destroy(state)

      expect(state).not_to have_key(:server_id)
      expect(state).not_to have_key(:hostname)
    end

    it "clears the credentials it put into state" do
      state = { server_id: "vm-1", hostname: "10.0.0.5", password: "s3cret", ssh_key: "/tmp/k.pem" }
      build_driver.destroy(state)

      expect(state).not_to have_key(:password)
      expect(state).not_to have_key(:ssh_key)
    end

    it "does nothing when there is no instance recorded" do
      build_driver.destroy({})

      expect(client.called?(:destroy_virtual_machine)).to be(false)
    end
  end

  describe "#status" do
    it "reports a running instance as live" do
      status = build_driver.status(server_id: "vm-1")

      expect(status[:live]).to be(true)
      expect(status[:state]).to eq("Running")
    end

    it "reports a stopped instance as not live" do
      client = DriverFakeClient.new(vm_info: vm_info, vm_state: "Stopped")
      driver = described_class.new(base_config)
      allow(driver).to receive(:client).and_return(client)

      expect(driver.status(server_id: "vm-1")[:live]).to be(false)
    end

    it "reports an unknown state when no instance has been created" do
      expect(build_driver.status({})[:state]).to eq("unknown")
    end
  end

  describe "#doctor" do
    # doctor reports through warn; capture the messages rather than the log
    # format so the assertions are about what it found, not how it printed it.
    def doctor_run(config = {})
      driver = build_driver(config)
      messages = []
      allow(driver).to receive(:warn) { |m| messages << m }
      [driver.doctor({}), messages]
    end

    it "reports the credentials the base config leaves unset" do
      found, messages = doctor_run

      expect(found).to be(true)
      expect(messages.join("\n")).to include("cloudstack_api_key is not set")
      expect(messages.join("\n")).to include("cloudstack_secret_key is not set")
    end

    it "names every missing setting in one run rather than one per run" do
      driver = described_class.new({})
      messages = []
      allow(driver).to receive(:warn) { |m| messages << m }

      driver.doctor({})

      %w{cloudstack_api_url cloudstack_api_key cloudstack_secret_key
         cloudstack_template_id cloudstack_serviceoffering_id
         cloudstack_zone_id}.each do |key|
        expect(messages.join("\n")).to include("#{key} is not set")
      end
    end

    it "passes when everything is set and CloudStack answers" do
      found, messages = doctor_run(
        cloudstack_api_key: "key", cloudstack_secret_key: "secret"
      )

      expect(found).to be(false)
      expect(messages).to be_empty
    end

    it "reports an api url that is not a URL" do
      found, messages = doctor_run(
        cloudstack_api_url: "not a url", cloudstack_api_key: "key",
        cloudstack_secret_key: "secret"
      )

      expect(found).to be(true)
      expect(messages.join("\n")).to match(/is not a URL|has no host/)
    end

    it "reports credentials CloudStack rejects" do
      driver = build_driver(
        cloudstack_api_key: "key", cloudstack_secret_key: "secret"
      )
      allow(driver.client.api).to receive(:list_zones)
        .and_raise(StandardError.new("401 unauthorized"))
      messages = []
      allow(driver).to receive(:warn) { |m| messages << m }

      expect(driver.doctor({})).to be(true)
      expect(messages.join("\n")).to include("rejected the configured credentials")
    end

    it "stays quiet about connectivity when the endpoint is missing" do
      driver = described_class.new({})
      messages = []
      allow(driver).to receive(:warn) { |m| messages << m }

      driver.doctor({})

      expect(messages.join("\n")).not_to include("rejected the configured credentials")
    end
  end

  describe "transport awareness" do
    context "with a WinRM transport" do
      let(:transport) { Kitchen::Transport::Winrm.new }

      it "forwards the WinRM port instead of SSH" do
        state = {}
        build_driver(associate_public_ip: true).create(state)

        expect(client.call_named(:create_port_forwarding_rule)["publicport"]).to eq(5985)
      end
    end

    context "with an SSH transport" do
      it "forwards the SSH port" do
        state = {}
        build_driver(associate_public_ip: true).create(state)

        expect(client.call_named(:create_port_forwarding_rule)["publicport"]).to eq(22)
      end
    end
  end
end
