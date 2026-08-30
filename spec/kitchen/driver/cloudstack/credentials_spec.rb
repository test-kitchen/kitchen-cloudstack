require "spec_helper"
require "kitchen/driver/cloudstack/credentials"
require "tmpdir"
require "fileutils"

RSpec.describe Kitchen::Driver::Cloudstack::Credentials do
  around do |example|
    Dir.mktmpdir do |dir|
      @home = File.join(dir, "home")
      @cwd = File.join(dir, "cwd")
      @search = File.join(dir, "search")
      [@home, @cwd, @search, File.join(@home, ".ssh")].each { |d| FileUtils.mkdir_p(d) }
      example.run
    end
  end

  def write_key(dir, name, contents = "-----BEGIN RSA PRIVATE KEY-----\n")
    path = File.join(dir, "#{name}.pem")
    File.write(path, contents)
    path
  end

  def state_for(config, server_info = {})
    described_class.new(config, home: @home, working_dir: @cwd).to_state(server_info)
  end

  describe "username and port precedence" do
    it "does not set a username when the driver was not configured with one" do
      expect(state_for({})).not_to have_key(:username)
    end

    it "sets the username when the driver was explicitly configured with one" do
      expect(state_for(username: "ubuntu")[:username]).to eq("ubuntu")
    end

    it "does not set a port when the driver was not configured with one" do
      expect(state_for({})).not_to have_key(:port)
    end

    it "sets the port when the driver was explicitly configured with one" do
      expect(state_for(port: 2222)[:port]).to eq(2222)
    end
  end

  describe "credential selection" do
    it "uses a keypair found in the configured search directory" do
      path = write_key(@search, "TestKey")
      result = state_for(
        cloudstack_ssh_keypair_name: "TestKey",
        keypair_search_directory: @search
      )

      expect(result[:ssh_key]).to eq(path)
    end

    it "finds a keypair in the working directory" do
      path = write_key(@cwd, "TestKey")
      result = state_for(cloudstack_ssh_keypair_name: "TestKey")

      expect(result[:ssh_key]).to eq(path)
    end

    it "finds a keypair in the home directory's .ssh" do
      path = write_key(File.join(@home, ".ssh"), "TestKey")
      result = state_for(cloudstack_ssh_keypair_name: "TestKey")

      expect(result[:ssh_key]).to eq(path)
    end

    it "uses the CloudStack generated password for a password-enabled template" do
      result = state_for({}, "passwordenabled" => true, "password" => "generated-pw")

      expect(result[:password]).to eq("generated-pw")
    end

    it "prefers a keypair over the CloudStack generated password" do
      write_key(@search, "TestKey")
      result = state_for(
        { cloudstack_ssh_keypair_name: "TestKey", keypair_search_directory: @search },
        "passwordenabled" => true, "password" => "generated-pw"
      )

      expect(result[:ssh_key]).not_to be_nil
      expect(result).not_to have_key(:password)
    end

    it "prefers the CloudStack generated password over a configured password" do
      result = state_for({ password: "configured-pw" },
        "passwordenabled" => true, "password" => "generated-pw")

      expect(result[:password]).to eq("generated-pw")
    end

    it "falls back to the configured password when nothing else is available" do
      expect(state_for(password: "configured-pw")[:password]).to eq("configured-pw")
    end

    it "sets no credentials when none can be determined" do
      result = state_for({})

      expect(result).not_to have_key(:password)
      expect(result).not_to have_key(:ssh_key)
    end
  end

  describe "warnings" do
    it "warns when the configured keypair file is a public key" do
      write_key(@search, "TestKey", "ssh-rsa AAAAB3Nza user@host\n")
      creds = described_class.new(
        { cloudstack_ssh_keypair_name: "TestKey", keypair_search_directory: @search },
        home: @home, working_dir: @cwd
      )
      creds.to_state({})

      expect(creds.warnings.join).to match(/not a private key/i)
    end

    # The old check compared the first token against a short list of public
    # key types, so anything outside that list -- and the list did not even
    # name ssh-dss correctly -- was accepted as a private key.
    it "warns about a public key type the old prefix list did not name" do
      write_key(@search, "TestKey", "ecdsa-sha2-nistp521 AAAAE2VjZHNh user@host\n")
      creds = described_class.new(
        { cloudstack_ssh_keypair_name: "TestKey", keypair_search_directory: @search },
        home: @home, working_dir: @cwd
      )
      creds.to_state({})

      expect(creds.warnings.join).to match(/not a private key/i)
    end

    it "warns when the file is a PuTTY key rather than a PEM" do
      write_key(@search, "TestKey", "PuTTY-User-Key-File-3: ssh-ed25519\nEncryption: none\n")
      creds = described_class.new(
        { cloudstack_ssh_keypair_name: "TestKey", keypair_search_directory: @search },
        home: @home, working_dir: @cwd
      )
      creds.to_state({})

      expect(creds.warnings.join).to match(/not a private key/i)
    end

    it "warns when the file is empty" do
      write_key(@search, "TestKey", "")
      creds = described_class.new(
        { cloudstack_ssh_keypair_name: "TestKey", keypair_search_directory: @search },
        home: @home, working_dir: @cwd
      )
      creds.to_state({})

      expect(creds.warnings.join).to match(/not a private key/i)
    end

    it "stays quiet about an OpenSSH format private key" do
      write_key(@search, "TestKey", "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk=\n")
      creds = described_class.new(
        { cloudstack_ssh_keypair_name: "TestKey", keypair_search_directory: @search },
        home: @home, working_dir: @cwd
      )
      creds.to_state({})

      expect(creds.warnings).to be_empty
    end

    it "warns when a keypair is named but no matching file is found" do
      creds = described_class.new(
        { cloudstack_ssh_keypair_name: "Missing" }, home: @home, working_dir: @cwd
      )
      creds.to_state({})

      expect(creds.warnings.join).to match(/no Missing\.pem was found/i)
    end
  end
end
