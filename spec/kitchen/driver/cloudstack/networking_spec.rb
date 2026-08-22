require "spec_helper"
require "kitchen/driver/cloudstack/networking"

RSpec.describe Kitchen::Driver::Cloudstack::Networking do
  # Records every API call and replays canned responses per request name.
  class RecordingCompute
    attr_reader :calls

    def initialize(responses = {})
      @responses = responses
      @calls = []
    end

    def method_missing(name, *args)
      @calls << [name, args.first]
      response = @responses[name]
      raise response if response.is_a?(Exception)

      response || {}
    end

    def respond_to_missing?(_name, _include_private = false) = true

    def call_named(name) = calls.find { |call| call.first == name }&.last
  end

  # Returns the "jobresult" straight from the canned response envelope.
  class FakeClient
    attr_reader :compute

    def initialize(compute, job_results = {})
      @compute = compute
      @job_results = job_results
    end

    def run_response_job(response, key)
      @job_results[key] || response.fetch(key, {})["jobresult"] || {}
    end
  end

  let(:associate_response) do
    { "associateipaddressresponse" => { "jobid" => "job-ip", "id" => "ip-uuid" } }
  end

  let(:job_results) do
    {
      "associateipaddressresponse" => { "ipaddress" => { "id" => "ip-uuid", "ipaddress" => "203.0.113.9" } },
      "createfirewallruleresponse" => { "firewallrule" => { "id" => "fw-1" } },
    }
  end

  def networking(config: {}, port: 22, responses: {}, results: job_results)
    compute = RecordingCompute.new({ associate_ip_address: associate_response }.merge(responses))
    described_class.new(
      { cloudstack_zone_id: "zone-1", cloudstack_network_id: "net-1" }.merge(config),
      client: FakeClient.new(compute, results), port: port
    ).tap { |n| n.instance_variable_set(:@recording_compute, compute) }
  end

  def compute_of(net) = net.instance_variable_get(:@recording_compute)

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

      expect(compute_of(net).call_named(:create_firewall_rule)).to be_nil
    end

    it "opens the transport's port when a firewall rule is requested" do
      net = networking(config: { cloudstack_create_firewall_rule: true }, port: 5985)
      net.associate_public_ip({})

      rule = compute_of(net).call_named(:create_firewall_rule)
      expect(rule["startport"]).to eq(5985)
      expect(rule["endport"]).to eq(5985)
    end

    it "opens the firewall to everywhere by default" do
      net = networking(config: { cloudstack_create_firewall_rule: true })
      net.associate_public_ip({})

      expect(compute_of(net).call_named(:create_firewall_rule)["cidrlist"]).to eq("0.0.0.0/0")
    end

    it "restricts the firewall rule to a configured CIDR" do
      net = networking(config: {
        cloudstack_create_firewall_rule: true,
        cloudstack_firewall_cidr: "198.51.100.0/24",
      })
      net.associate_public_ip({})

      expect(compute_of(net).call_named(:create_firewall_rule)["cidrlist"]).to eq("198.51.100.0/24")
    end

    it "records the firewall rule id so teardown can remove it" do
      net = networking(config: { cloudstack_create_firewall_rule: true })
      state = {}
      net.associate_public_ip(state)

      expect(state[:firewall_rule_id]).to eq("fw-1")
    end
  end

  describe "#create_port_forward" do
    it "forwards the transport's port rather than always SSH" do
      net = networking(port: 5985)
      net.create_port_forward({ ipaddressid: "ip-uuid" }, "vm-1")

      rule = compute_of(net).call_named(:create_port_forwarding_rule)
      expect(rule["privateport"]).to eq(5985)
      expect(rule["publicport"]).to eq(5985)
    end

    it "forwards SSH for the default transport" do
      net = networking(port: 22)
      net.create_port_forward({ ipaddressid: "ip-uuid" }, "vm-1")

      expect(compute_of(net).call_named(:create_port_forwarding_rule)["privateport"]).to eq(22)
    end
  end

  describe "#teardown" do
    it "deletes the port forwarding rule before releasing the address" do
      net = networking
      net.teardown(ipaddressid: "ip-uuid", forwardingruleid: "fwd-1")

      names = compute_of(net).calls.map(&:first)
      expect(names.index(:delete_port_forwarding_rule)).to be < names.index(:disassociate_ip_address)
    end

    it "deletes a firewall rule when one was created" do
      net = networking
      net.teardown(ipaddressid: "ip-uuid", firewall_rule_id: "fw-1")

      expect(compute_of(net).calls.map(&:first)).to include(:delete_firewall_rule)
    end

    it "ignores resources CloudStack reports as already gone" do
      gone = Fog::Cloudstack::Compute::BadRequest.new("Entity does not exist")
      net = networking(responses: { disassociate_ip_address: gone })

      expect { net.teardown(ipaddressid: "ip-uuid") }.not_to raise_error
    end

    it "does nothing when no public address was ever associated" do
      net = networking
      net.teardown({})

      expect(compute_of(net).calls).to be_empty
    end
  end
end
