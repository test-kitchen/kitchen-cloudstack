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

  # A blank line used to satisfy the "already base64" check, because ^ and $
  # anchor to a line rather than to the whole string and every branch of the
  # pattern is optional, so an empty line matched. Cloud-config and shell
  # scripts are full of blank lines, so the ordinary case went to CloudStack
  # unencoded.
  it "base64-encodes userdata containing a blank line" do
    data = "#cloud-config\n\npackages:\n - htop\n"
    opts = options_for(base_config.merge(cloudstack_userdata: data))

    expect(opts[:userdata]).not_to eq(data)
    expect(Base64.decode64(opts[:userdata])).to eq(data)
  end

  it "base64-encodes a shell script whose sections are separated by blank lines" do
    data = "#!/bin/bash\n\necho hello\n"
    opts = options_for(base_config.merge(cloudstack_userdata: data))

    expect(opts[:userdata]).not_to eq(data)
    expect(Base64.decode64(opts[:userdata])).to eq(data)
  end

  it "sends userdata on one line so no line break reaches the query string" do
    data = "#cloud-config\npackages:\n" + (" - htop\n" * 20)
    opts = options_for(base_config.merge(cloudstack_userdata: data))

    expect(opts[:userdata]).not_to include("\n")
    expect(Base64.decode64(opts[:userdata])).to eq(data)
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
end
