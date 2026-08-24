require "spec_helper"
require "kitchen/driver/cloudstack/server_options"

RSpec.describe Kitchen::Driver::Cloudstack::ServerOptions do
  let(:base_config) do
    {
      cloudstack_template_id: "tmpl-1",
      cloudstack_serviceoffering_id: "offer-1",
      cloudstack_zone_id: "zone-1",
    }
  end

  def options_for(config, instance_name: "default-ubuntu", login: "tsmith", hostname: "workstation")
    described_class.new(
      config, instance_name: instance_name, login: login, hostname: hostname
    ).to_h
  end

  it "always includes the template, service offering and zone ids" do
    opts = options_for(base_config)

    expect(opts[:templateid]).to eq("tmpl-1")
    expect(opts[:serviceofferingid]).to eq("offer-1")
    expect(opts[:zoneid]).to eq("zone-1")
  end

  it "omits optional values that were not configured" do
    opts = options_for(base_config)

    expect(opts).not_to have_key("networkids")
    expect(opts).not_to have_key("keypair")
    expect(opts).not_to have_key("diskofferingid")
  end

  it "includes optional values that were configured" do
    opts = options_for(base_config.merge(
      cloudstack_network_id: "net-1",
      cloudstack_ssh_keypair_name: "TestKey"
    ))

    expect(opts["networkids"]).to eq("net-1")
    expect(opts["keypair"]).to eq("TestKey")
  end

  it "base64-encodes plain userdata" do
    opts = options_for(base_config.merge(cloudstack_userdata: "#cloud-config\npackages:\n - htop\n"))

    expect(Base64.decode64(opts[:userdata])).to eq("#cloud-config\npackages:\n - htop\n")
  end

  it "passes through userdata that is already base64" do
    already_encoded = Base64.encode64("#cloud-config\n")
    opts = options_for(base_config.merge(cloudstack_userdata: already_encoded))

    expect(opts[:userdata]).to eq(already_encoded)
  end

  it "generates a display name from the instance name when none is configured" do
    opts = options_for(base_config, instance_name: "default-ubuntu")

    expect(opts["displayname"]).to start_with("default-ubuntu-")
  end

  it "keeps the generated name within CloudStack's 64 character limit" do
    opts = options_for(base_config, instance_name: "a-really-long-suite-name-that-goes-on-and-on-forever")

    expect(opts["displayname"].length).to be <= 64
  end

  it "keeps the name within 64 characters even when every component is oversized" do
    opts = options_for(
      base_config,
      instance_name: "a" * 40,
      login: "b" * 40,
      hostname: "c" * 40
    )

    expect(opts["displayname"].length).to be <= 64
  end

  it "uses the configured server name verbatim when given" do
    opts = options_for(base_config.merge(server_name: "my-server"))

    expect(opts["displayname"]).to eq("my-server")
  end

  it "deploys into a configured project" do
    opts = options_for(base_config.merge(cloudstack_project_id: "proj-1"))

    expect(opts["projectid"]).to eq("proj-1")
  end

  it "omits the project when none is configured" do
    expect(options_for(base_config)).not_to have_key("projectid")
  end

  describe "custom service offering sizing" do
    # CloudStack takes this as a map. Sent as flat "details[0].cpuNumber"
    # parameters they are rejected as unknown, so the shape matters.
    it "sends the sizing as a details map" do
      opts = options_for(base_config.merge(
        cloudstack_serviceoffering_cpu: 2,
        cloudstack_serviceoffering_cpuspeed: 2000,
        cloudstack_serviceoffering_memory: 4096
      ))

      expect(opts["details"]).to eq([{ "cpuNumber" => 2, "cpuSpeed" => 2000, "memory" => 4096 }])
    end

    it "sends only the sizing values that were configured" do
      opts = options_for(base_config.merge(cloudstack_serviceoffering_memory: 4096))

      expect(opts["details"]).to eq([{ "memory" => 4096 }])
    end

    it "omits the details map when no sizing was configured" do
      expect(options_for(base_config)).not_to have_key("details")
    end

    it "does not send the sizing as flat parameters" do
      opts = options_for(base_config.merge(cloudstack_serviceoffering_cpu: 2))

      expect(opts.keys.grep(/details\[/)).to be_empty
    end
  end
end
