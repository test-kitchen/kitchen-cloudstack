# kitchen-cloudstack

[![Gem Version](https://badge.fury.io/rb/kitchen-cloudstack.svg)](https://badge.fury.io/rb/kitchen-cloudstack)

A [Test Kitchen](https://kitchen.ci/) driver for [Apache CloudStack](https://cloudstack.apache.org/) and Citrix CloudPlatform. It deploys and destroys CloudStack virtual machines so you can test your cookbooks and infrastructure code against them.

> **Compatibility warning**
>
> This driver is built on `Kitchen::Driver::SSHBase`, which was **removed in
> Test Kitchen 4.0**. The gemspec still allows `test-kitchen < 5`, so the gem
> will install alongside a current Test Kitchen and then fail at load time with
> a `NameError`.
>
> To use it today you must pin Test Kitchen below 4.0. That also means it will
> not work with the Test Kitchen bundled in current Cinc Workstation or Chef
> Workstation. Porting the driver onto the modern transport API is the real
> fix, and contributions doing so are very welcome.

<!-- -->

> This documentation uses [Cinc Workstation](https://cinc.sh/) and the `cinc` commands throughout. Everything here works identically with Chef Workstation — see [Using with Chef](#using-with-chef).

## Requirements

- An Apache CloudStack or Citrix CloudPlatform deployment
- API credentials for it: an API key, a secret key, and the API URL
- Test Kitchen older than 4.0, for the reason described above
- `fog-cloudstack`, installed automatically as a dependency

## Installation

Because of the version pin described above, install this driver into a
project-local bundle rather than into Workstation:

```ruby
# Gemfile
source "https://rubygems.org"

gem "test-kitchen", "< 4.0"
gem "kitchen-cloudstack"
```

Then:

```sh
bundle install
```

Run the commands below through `bundle exec` so the pinned Test Kitchen is used.

## Authentication

The driver needs three values, which you can find in the CloudStack UI under
your account's API keys:

```yaml
driver:
  name: cloudstack
  cloudstack_api_key: <%= ENV['CLOUDSTACK_API_KEY'] %>
  cloudstack_secret_key: <%= ENV['CLOUDSTACK_SECRET_KEY'] %>
  cloudstack_api_url: https://cloudstack.example.com/client/api
```

Keep the keys out of `kitchen.yml` by reading them from the environment as
shown above.

## Quick Start

```yaml
---
driver:
  name: cloudstack
  cloudstack_api_key: <%= ENV['CLOUDSTACK_API_KEY'] %>
  cloudstack_secret_key: <%= ENV['CLOUDSTACK_SECRET_KEY'] %>
  cloudstack_api_url: https://cloudstack.example.com/client/api

provisioner:
  name: cinc_infra

platforms:
  - name: ubuntu-22.04
    driver:
      cloudstack_template_id: 8a4e1c1f-1234-4b8b-9c2f-77b6c9f0e111
      cloudstack_serviceoffering_id: b1d2f3a4-5678-4c9d-8e1f-99a7b6c5d4e3
      cloudstack_zone_id: c2e3f4b5-9012-4d0e-9f2a-11b3c5d7e9f1

suites:
  - name: default
    run_list:
      - recipe[my_cookbook::default]
```

Then run the full test cycle:

```sh
bundle exec cinc kitchen test
```

Or step through it:

```sh
bundle exec cinc kitchen create    # deploy the CloudStack VM
bundle exec cinc kitchen converge  # apply your cookbook
bundle exec cinc kitchen verify    # run your tests
bundle exec cinc kitchen destroy   # destroy the VM
```

Template, service offering, and zone are usually set per platform, since they
are what differs between operating systems. Everything else usually belongs in
the top-level `driver:` block.

## Configuration

Options can be set under the top-level `driver:` key, or per platform under
`platforms[].driver:`.

### Credentials

| Option | Default | Description |
| --- | --- | --- |
| `cloudstack_api_key` | *none* | CloudStack API key. Required. |
| `cloudstack_secret_key` | *none* | CloudStack secret key. Required. |
| `cloudstack_api_url` | *none* | Full URL of the CloudStack API endpoint, e.g. `https://cloudstack.example.com/client/api`. Required. |
| `disable_ssl_validation` | `false` | Skip TLS certificate validation. Only use this against a deployment with an invalid certificate, and only if you understand the risk. |

### Instance

| Option | Default | Description |
| --- | --- | --- |
| `cloudstack_template_id` | *none* | ID of the template (OS image) to deploy. Required, normally set per platform. |
| `cloudstack_serviceoffering_id` | *none* | ID of the service offering, which determines CPU and memory. Required, normally set per platform. |
| `cloudstack_zone_id` | *none* | ID of the zone to deploy into. Required, normally set per platform. |
| `cloudstack_project_id` | *unset* | ID of a project to deploy the VM into. |
| `cloudstack_affinity_group_id` | *unset* | ID of an affinity group, for pinning to a dedicated cluster. |
| `cloudstack_expunge` | `false` | Expunge the VM on destroy rather than leaving it in the Destroyed state. |

### Custom service offering sizing

These apply only when the service offering itself does not specify CPU or memory.

| Option | Default | Description |
| --- | --- | --- |
| `cloudstack_serviceoffering_cpu` | *from offering* | Number of CPUs. |
| `cloudstack_serviceoffering_cpuspeed` | *from offering* | Speed of each CPU, in MHz. |
| `cloudstack_serviceoffering_memory` | *from offering* | Memory, in MB. |

### Disk

| Option | Default | Description |
| --- | --- | --- |
| `cloudstack_diskoffering_id` | *unset* | ID of a disk offering to attach a data disk from. |
| `cloudstack_diskoffering_size` | *from offering* | Size of the data disk in GB, for a custom disk offering. |

### Networking

| Option | Default | Description |
| --- | --- | --- |
| `cloudstack_network_id` | *unset* | Network ID, for isolated or VPC networks. |
| `cloudstack_security_group_id` | *unset* | Security group ID, for shared networks. |
| `associate_public_ip` | `false` | Acquire a public IP and set up static NAT automatically. |
| `cloudstack_vm_public_ip` | *unset* | Public IP to connect to, when you configure advanced networking and static NAT yourself. |
| `cloudstack_create_firewall_rule` | `false` | Create a firewall rule opening SSH (port 22) to the public IP. |

### SSH and access

| Option | Default | Description |
| --- | --- | --- |
| `username` | `"root"` | User to connect as. |
| `port` | `"22"` | SSH port. |
| `password` | *generated by CloudStack* | Password to connect with. By default the driver uses the password CloudStack generates. |
| `cloudstack_ssh_keypair_name` | *unset* | Name of a CloudStack SSH keypair to deploy with. See [SSH keypairs](#ssh-keypairs). |
| `keypair_search_directory` | *see below* | Extra directory to search for the keypair's `.pem` file. |
| `cloudstack_sync_time` | `0` | Seconds to sleep after connecting, to let `cloud-set-guest-password` or `cloud-set-guest-sshkey` finish. Raise this if logins fail intermittently just after boot. |

### Naming

| Option | Default | Description |
| --- | --- | --- |
| `server_name` | *generated* | Display name of the VM in CloudStack. |
| `host_name` | *generated* | Hostname set on the VM itself. Useful when long generated hostnames cause `ENAMETOOLONG` errors during a converge. |
| `name` | *generated* | Name used for the instance, generated from the suite name and your login if unset. |

### Other

| Option | Default | Description |
| --- | --- | --- |
| `cloudstack_userdata` | *unset* | User data passed to the VM. Must be a double-quoted string, so escapes such as `\n` are interpreted. |

## SSH keypairs

To use a CloudStack SSH keypair, set `cloudstack_ssh_keypair_name` and make the
matching **private** key available as a `.pem` file. The driver looks for a file
named after the keypair with a `.pem` suffix — a keypair called `TestKey` needs
`TestKey.pem` — in these locations:

1. the directory containing your `kitchen.yml`
2. your home directory (`~`)
3. your `~/.ssh` directory
4. the directory given by `keypair_search_directory`, specified without a trailing slash

Note that this file must be the **private** key, not the public key.

```yaml
driver:
  name: cloudstack
  cloudstack_ssh_keypair_name: TestKey
  keypair_search_directory: /home/me/cloudstack-keys
```

## Examples

### User data

The value must be double-quoted so the escape sequences are interpreted:

```yaml
driver:
  name: cloudstack
  cloudstack_userdata: "#cloud-config\npackages:\n - htop\n"
```

### Advanced networking with an automatic public IP

```yaml
driver:
  name: cloudstack
  cloudstack_network_id: d3f4a5b6-3456-4e1f-8a2b-33c5d7e9f1a2
  associate_public_ip: true
  cloudstack_create_firewall_rule: true
```

### Static NAT configured by hand

```yaml
driver:
  name: cloudstack
  cloudstack_network_id: d3f4a5b6-3456-4e1f-8a2b-33c5d7e9f1a2
  cloudstack_vm_public_ip: 203.0.113.25
```

### Shared network with a security group

```yaml
driver:
  name: cloudstack
  cloudstack_security_group_id: e4a5b6c7-7890-4f2a-9b3c-44d6e8f0a2b3
```

### A custom-sized service offering

```yaml
driver:
  name: cloudstack
  cloudstack_serviceoffering_id: f5b6c7d8-1234-4a3b-8c4d-55e7f9a1b3c4
  cloudstack_serviceoffering_cpu: 4
  cloudstack_serviceoffering_cpuspeed: 2000
  cloudstack_serviceoffering_memory: 8192
  cloudstack_diskoffering_id: a6c7d8e9-5678-4b4c-9d5e-66f8a0b2c4d5
  cloudstack_diskoffering_size: 100
```

### Avoiding ENAMETOOLONG during a converge

```yaml
driver:
  name: cloudstack
  host_name: kitchen-test
```

### Cleaning up fully

```yaml
driver:
  name: cloudstack
  cloudstack_expunge: true
```

## Troubleshooting

**`NameError: uninitialized constant Kitchen::Driver::SSHBase`.** You are running
Test Kitchen 4.0 or newer. See the compatibility warning at the top: pin
`test-kitchen` below 4.0.

**Login fails immediately after the VM boots.** CloudStack's
`cloud-set-guest-password` and `cloud-set-guest-sshkey` scripts may not have run
yet. Increase `cloudstack_sync_time`.

**Converge fails with `ENAMETOOLONG`.** The generated hostname is too long for
the run. Set `host_name` to something short.

## Using with Chef

This driver is not tied to Cinc. The examples above use Cinc Workstation and the `cinc_infra` provisioner, but the driver works exactly the same with [Chef Workstation](https://www.chef.io/downloads/tools/workstation) — run `kitchen` instead of `cinc kitchen`, and use `chef_infra` instead of `cinc_infra`:

```yaml
provisioner:
  name: chef_infra
```

The same Test Kitchen version pin applies either way.

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/test-kitchen/kitchen-cloudstack). Porting the driver off the removed `SSHBase` class would be especially valuable. See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and the state of the test tooling.

## Authors

Created and maintained by [Jeff Moody](https://github.com/fifthecho) (<fifthecho@gmail.com>).

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](https://github.com/test-kitchen/kitchen-cloudstack/blob/main/LICENSE) for details.
