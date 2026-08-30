require "spec_helper"
require "kitchen/driver/cloudstack/networking"

RSpec.describe Kitchen::Driver::Cloudstack::Networking do
  # Records every API call and replays canned responses per command name.
  #
  # Asynchronous commands are called with +sync: true+, so each one answers
  # with CloudStack's immediate response -- an id and a job id -- rather than
  # the finished job result.
  class RecordingApi
    attr_reader :calls

    def initialize(responses = {})
      @responses = responses
      @calls = []
    end

    def method_missing(name, *args)
      @calls << [name, args.first]
      response = @responses[name]
      raise response if response.is_a?(Exception)

      response || { "id" => "#{name}-id", "jobid" => "#{name}-job" }
    end

    def respond_to_missing?(_name, _include_private = false) = true

    def call_named(name) = calls.find { |call| call.first == name }&.last
  end

  # Answers job results by job id.
  class FakeClient
    attr_reader :api

    def initialize(api, job_results = {})
      @api = api
      @job_results = job_results
    end

    def run_job(jobid) = @job_results.fetch(jobid, {})
  end

  let(:associate_response) do
    { "jobid" => "job-ip", "id" => "ip-uuid" }
  end

  let(:job_results) do
    {
      "job-ip" => { "ipaddress" => { "id" => "ip-uuid", "ipaddress" => "203.0.113.9" } },
      "create_firewall_rule-job" => { "firewallrule" => { "id" => "fw-1" } },
    }
  end

  def networking(config: {}, port: 22, responses: {}, results: job_results)
    api = RecordingApi.new({ associate_ip_address: associate_response }.merge(responses))
    described_class.new(
      { cloudstack_zone_id: "zone-1", cloudstack_network_id: "net-1" }.merge(config),
      client: FakeClient.new(api, results), port: port
    ).tap { |n| n.instance_variable_set(:@recording_api, api) }
  end

  def api_of(net) = net.instance_variable_get(:@recording_api)

  describe "#associate_public_ip" do
    it "returns the allocated public IP address" do
      state = {}
      expect(networking.associate_public_ip(state)).to eq("203.0.113.9")
    end

    it "records the public IP address id in state so it can be released" do
      net = networking
      state = {}
      net.associate_public_ip(state)

      expect(state[:ipaddressid]).to eq("ip-uuid")
    end

    it "does not create a firewall rule unless one was requested" do
      net = networking
      net.associate_public_ip({})

      expect(api_of(net).call_named(:create_firewall_rule)).to be_nil
    end

    it "opens the transport's port when a firewall rule is requested" do
      net = networking(config: { cloudstack_create_firewall_rule: true }, port: 5985)
      net.associate_public_ip({})

      rule = api_of(net).call_named(:create_firewall_rule)
      expect(rule["startport"]).to eq(5985)
      expect(rule["endport"]).to eq(5985)
    end

    it "opens the firewall to everywhere by default" do
      net = networking(config: { cloudstack_create_firewall_rule: true })
      net.associate_public_ip({})

      expect(api_of(net).call_named(:create_firewall_rule)["cidrlist"]).to eq("0.0.0.0/0")
    end

    it "restricts the firewall rule to a configured CIDR" do
      net = networking(config: {
        cloudstack_create_firewall_rule: true,
        cloudstack_firewall_cidr: "198.51.100.0/24",
      })
      net.associate_public_ip({})

      expect(api_of(net).call_named(:create_firewall_rule)["cidrlist"]).to eq("198.51.100.0/24")
    end

    it "records the firewall rule id so teardown can remove it" do
      net = networking(config: { cloudstack_create_firewall_rule: true })
      state = {}
      net.associate_public_ip(state)

      expect(state[:firewall_rule_id]).to eq("fw-1")
    end
  end

  describe "project scoping" do
    # fog applied the project to every request from the connection itself.
    # cloudstack_client has no equivalent, so each command that accepts a
    # project has to be given one.
    it "allocates the address inside a configured project" do
      net = networking(config: { cloudstack_project_id: "proj-1" })
      net.associate_public_ip({})

      expect(api_of(net).call_named(:associate_ip_address)["projectid"]).to eq("proj-1")
    end

    it "looks for the network inside a configured project" do
      net = networking(config: { cloudstack_project_id: "proj-1" })
      net.associate_public_ip({})

      expect(api_of(net).call_named(:list_networks)["projectid"]).to eq("proj-1")
    end
  end

  describe "#create_port_forward" do
    it "forwards the transport's port rather than always SSH" do
      net = networking(port: 5985)
      net.create_port_forward({ ipaddressid: "ip-uuid" }, "vm-1")

      rule = api_of(net).call_named(:create_port_forwarding_rule)
      expect(rule["privateport"]).to eq(5985)
      expect(rule["publicport"]).to eq(5985)
    end

    it "forwards SSH for the default transport" do
      net = networking(port: 22)
      net.create_port_forward({ ipaddressid: "ip-uuid" }, "vm-1")

      expect(api_of(net).call_named(:create_port_forwarding_rule)["privateport"]).to eq(22)
    end

    # openfirewall defaults to true on a non-VPC network, so the driver has to
    # say false explicitly or CloudStack opens the firewall itself -- creating
    # a rule teardown does not know about. cloudstack_client drops arguments
    # whose value is falsey, so this has to be the string "false".
    it "asks CloudStack not to open the firewall itself" do
      net = networking(port: 22)
      net.create_port_forward({ ipaddressid: "ip-uuid" }, "vm-1")

      expect(api_of(net).call_named(:create_port_forwarding_rule)["openfirewall"]).to eq("false")
    end

    it "records the forwarding rule id before waiting for the job" do
      net = networking(port: 22)
      state = { ipaddressid: "ip-uuid" }
      net.create_port_forward(state, "vm-1")

      expect(state[:forwardingruleid]).to eq("create_port_forwarding_rule-id")
    end
  end

  describe "#teardown" do
    it "deletes the port forwarding rule before releasing the address" do
      net = networking
      net.teardown(ipaddressid: "ip-uuid", forwardingruleid: "fwd-1")

      names = api_of(net).calls.map(&:first)
      expect(names.index(:delete_port_forwarding_rule)).to be < names.index(:disassociate_ip_address)
    end

    it "deletes a firewall rule when one was created" do
      net = networking
      net.teardown(ipaddressid: "ip-uuid", firewall_rule_id: "fw-1")

      expect(api_of(net).calls.map(&:first)).to include(:delete_firewall_rule)
    end

    it "deletes rules by id" do
      net = networking
      net.teardown(ipaddressid: "ip-uuid", forwardingruleid: "fwd-1")

      expect(api_of(net).call_named(:delete_port_forwarding_rule)).to eq({ "id" => "fwd-1" })
      expect(api_of(net).call_named(:disassociate_ip_address)).to eq({ "id" => "ip-uuid" })
    end

    it "ignores resources CloudStack reports as already gone" do
      gone = CloudstackClient::ApiError.new("Status 431: Entity does not exist.")
      net = networking(responses: { disassociate_ip_address: gone })

      expect { net.teardown(ipaddressid: "ip-uuid") }.not_to raise_error
    end

    it "still raises errors that are not an already-gone resource" do
      boom = CloudstackClient::ApiError.new("Status 431: Insufficient permissions.")
      net = networking(responses: { disassociate_ip_address: boom })

      expect { net.teardown(ipaddressid: "ip-uuid") }
        .to raise_error(CloudstackClient::ApiError, /Insufficient permissions/)
    end

    it "does nothing when no public address was ever associated" do
      net = networking
      net.teardown({})

      expect(api_of(net).calls).to be_empty
    end
  end
end
