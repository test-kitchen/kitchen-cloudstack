# kitchen-cloudstack

[![Gem Version](https://badge.fury.io/rb/kitchen-cloudstack.svg)](https://badge.fury.io/rb/kitchen-cloudstack)

A [Test Kitchen](https://kitchen.ci/) driver for [Apache CloudStack](https://cloudstack.apache.org/) and Citrix CloudPlatform. It deploys and destroys CloudStack virtual machines so you can test your cookbooks and infrastructure code against them.

> This documentation uses [Cinc Workstation](https://cinc.sh/) and the `cinc` commands throughout. Everything here works identically with Chef Workstation — see [Using with Chef](#using-with-chef).

## Requirements

- An Apache CloudStack or Citrix CloudPlatform deployment
- API credentials for it: an API key, a secret key, and the API URL
- Test Kitchen 3.0 or newer, including the version bundled with current Cinc
  Workstation and Chef Workstation
- `fog-cloudstack`, installed automatically as a dependency

## Installation

Install the driver alongside Test Kitchen:

```sh
gem install kitchen-cloudstack
```

Or, for a project-local bundle:

```ruby
# Gemfile
source "https://rubygems.org"

gem "test-kitchen"
gem "kitchen-cloudstack"
```

```sh
bundle install
```

If you installed into a bundle, run the commands below through `bundle exec`.

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
| `associate_public_ip` | `false` | Acquire a public IP and forward the transport's port to the instance. This is a port forwarding rule for that one port, not static NAT, so nothing else on the instance is reachable through the public address. |
| `cloudstack_vm_public_ip` | *unset* | Public IP to connect to, when you configure advanced networking and static NAT yourself. |
| `cloudstack_create_firewall_rule` | `false` | Create a firewall rule opening the transport's port to the public IP. |
| `cloudstack_firewall_cidr` | `0.0.0.0/0` | Source range the firewall rule allows. Narrow this to your own network rather than leaving it open to the internet. |

### SSH and access

| Option | Default | Description |
| --- | --- | --- |
| `username` | *transport default* | User to connect as. Leave unset to use the `transport:` setting. |
| `port` | *transport default* | Port to connect on. Leave unset to use the `transport:` setting. |
| `password` | *generated by CloudStack* | Password to connect with. By default the driver uses the password CloudStack generates. |
| `cloudstack_ssh_keypair_name` | *unset* | Name of a CloudStack SSH keypair to deploy with. See [SSH keypairs](#ssh-keypairs). |
| `keypair_search_directory` | *see below* | Extra directory to search for the keypair's `.pem` file. |
| `cloudstack_sync_time` | *unset* | Seconds to wait before connecting, to let `cloud-set-guest-password` or `cloud-set-guest-sshkey` finish. Raise this if logins fail intermittently just after boot. |

### Naming

| Option | Default | Description |
| --- | --- | --- |
| `server_name` | *generated* | Display name of the VM in CloudStack. |
| `host_name` | *generated* | Hostname set on the VM itself. Useful when long generated hostnames cause `ENAMETOOLONG` errors during a converge. |

### Other

| Option | Default | Description |
| --- | --- | --- |
| `cloudstack_userdata` | *unset* | User data passed to the VM. Must be a double-quoted string, so escapes such as `\n` are interpreted. |
| `cloudstack_job_poll_interval` | `10` | Seconds between checks on a running CloudStack job. |
| `cloudstack_job_timeout` | `600` | Seconds to wait for a CloudStack job before giving up. Raise this if deploys legitimately take longer. |

## SSH keypairs

To use a CloudStack SSH keypair, set `cloudstack_ssh_keypair_name` and make the
matching **private** key available as a `.pem` file. The driver looks for a file
named after the keypair with a `.pem` suffix — a keypair called `TestKey` needs
`TestKey.pem` — in these locations:

1. the directory given by `keypair_search_directory`, specified without a trailing slash
2. the directory containing your `kitchen.yml`
3. your home directory (`~`)
4. your `~/.ssh` directory

Note that this file must be the **private** key, not the public key.

```yaml
driver:
  name: cloudstack
  cloudstack_ssh_keypair_name: TestKey
  keypair_search_directory: /home/me/cloudstack-keys
```

## How credentials reach the instance

The driver does not connect to the instance itself. It works out an address and
a set of credentials, hands them to the configured Test Kitchen transport, and
waits for that transport to become ready. This is what lets the same driver
serve both Linux and Windows instances.

Credentials are chosen in this order:

1. a CloudStack SSH keypair, if `cloudstack_ssh_keypair_name` is set and the
   matching `.pem` is found
2. the password CloudStack generates, for a password-enabled template
3. the `password` you configured on the driver

`username` and `port` are only sent to the transport when you set them on the
driver. Leave them unset and your `transport:` configuration applies, which is
usually what you want:

```yaml
driver:
  name: cloudstack
  # no username here

transport:
  username: ubuntu   # honoured, because the driver does not override it
```

## Windows instances

Set the transport to WinRM and the driver follows it. Port forwarding and
firewall rules use the transport's port (5985, or 5986 for SSL) instead of SSH's
22, and the password CloudStack generates for a password-enabled Windows
template is handed to WinRM automatically:

```yaml
driver:
  name: cloudstack
  cloudstack_api_key: <%= ENV['CLOUDSTACK_API_KEY'] %>
  cloudstack_secret_key: <%= ENV['CLOUDSTACK_SECRET_KEY'] %>
  cloudstack_api_url: https://cloudstack.example.com/client/api
  associate_public_ip: true
  cloudstack_create_firewall_rule: true

transport:
  name: winrm

platforms:
  - name: windows-2022
    driver:
      cloudstack_template_id: <windows template id>
      cloudstack_serviceoffering_id: <offering id>
      cloudstack_zone_id: <zone id>
```

The template must have password management enabled so CloudStack can set and
report the administrator password, and WinRM must be listening in the image.

## Checking instance state

`kitchen list` asks the driver whether each instance is still alive, and this
driver answers from CloudStack rather than guessing, so an instance destroyed
out from under Test Kitchen is reported accurately.

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

The driver forwards only the port your transport connects on — 22 for SSH,
5985 or 5986 for WinRM — and, with `cloudstack_create_firewall_rule`, opens
that same one port. If you need other ports reachable from outside, set up
static NAT yourself and point the driver at the address with
`cloudstack_vm_public_ip`.

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

## Checking your configuration

The driver has no required settings, so a missing endpoint or credential is not
caught when Test Kitchen loads `kitchen.yml` — it surfaces part way through a
deploy. `kitchen doctor` moves that discovery earlier. It names every setting
you have left unset in one go, and then makes a real API call to confirm that
CloudStack accepts your keys:

```sh
bundle exec cinc kitchen doctor default-ubuntu
```

## Troubleshooting

**`NameError: uninitialized constant Kitchen::Driver::SSHBase`.** You are running
kitchen-cloudstack 0.24.0 or older, which was built on a class Test Kitchen
removed in 4.0. Upgrade to 1.0.0 or newer.

**A CloudStack job times out.** Deploys on a busy or large template can exceed
the ten minute default. Raise `cloudstack_job_timeout`.

**WinRM never becomes ready.** Check that the template has password management
enabled, that WinRM is listening in the image, and — if you are forwarding a
public IP — that `cloudstack_create_firewall_rule` is set so the WinRM port is
actually open.

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

Everything else works identically.

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/test-kitchen/kitchen-cloudstack). See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, the layout of the test suite, and the changes that would be most useful.

## Authors

Created and maintained by [Jeff Moody](https://github.com/fifthecho) (<fifthecho@gmail.com>).

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](https://github.com/test-kitchen/kitchen-cloudstack/blob/main/LICENSE) for details.
