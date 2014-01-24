# <a name="title"></a> Kitchen::CloudStack

A Test Kitchen Driver for Apache CloudStack / Citrix CloudPlatform.

## <a name="requirements"></a> Requirements

This Gem only requires FOG of a version greater than 1.3.1. However, as most of your knife plugins will be using newer
versions of FOG, that shouldn't be an issue.

## <a name="installation"></a> Installation and Setup

Please read the [Driver usage][driver_usage] page for more details.

## <a name="config"></a> Configuration

Provide, at a minimum, the required driver options in your `.kitchen.yml` file:

    driver_plugin: cloudstack
    driver_config:
      cloudstack_api_key: [YOUR CLOUDSTACK API KEY]
      cloudstack_secret_key: [YOUR CLOUDSTACK SECRET KEY]
      cloudstack_api_url: [YOUR CLOUDSTACK API URL]
      require_chef_omnibus: latest (if you'll be using Chef)
    OPTIONAL
      cloudstack_sync_time: [NUMBER OF SECONDS TO WAIT FOR CLOUD-SET-GUEST-PASSWORD/SSHKEY]
      keypair_search_directory: [PATH TO DIRECTORY (other than ~, ., and ~/.ssh) WITH KEYPAIR PEM FILE]

Then to specify different OS templates,

    platforms:
      cloudstack_template_id: [INSTANCE TEMPLATE ID]
      cloudstack_serviceoffering_id: [INSTANCE SERVICE OFFERING ID]
      cloudstack_zone_id: [INSTANCE ZONE ID]
      cloudstack_network_id: [NETWORK ID FOR ISOLATED OR VPC NETWORKS]
      cloudstack_security_group_id: [SECURITY GROUP ID FOR SHARED NETWORKS]
    OPTIONAL
      cloudstack_ssh_keypair_name: [SSH KEY NAME]
      cloudstack_sync_time: [NUMBER OF SECONDS TO WAIT FOR CLOUD-SET-GUEST-PASSWORD/SSHKEY]
To use the CloudStack public key provider, you need to have the .PEM file located in the same directory as
your .kitchen.yml file, your home directory (~), your .ssh directory (~/.ssh/), or specify a directory (without any
trailing slahses) as your "keypair_search_directory" and the file be named the same as the Keypair on CloudStack
suffixed with .pem (e.g. the Keypair named "TestKey" should be located in one of the searched directories and named
"TestKey.pem").

By default, a unique server name will be generated and the randomly generated password will be used, though that
behavior can be overridden with additional options (e.g., to specify a SSH private key):

    name: [A UNIQUE SERVER NAME]
    public_key_path: [PATH TO YOUR SSH PUBLIC KEY]
    username: [SSH USER]
    port: [SSH PORT]

Only disable SSL cert validation if you absolutely know what you are doing,
but are stuck with an CloudStack deployment without valid SSL certs.

    disable_ssl_validation: true

### <a name="config-require-chef-omnibus"></a> require\_chef\_omnibus

Determines whether or not a Chef [Omnibus package][chef_omnibus_dl] will be
installed. There are several different behaviors available:

* `true` - the latest release will be installed. Subsequent converges
  will skip re-installing if chef is present.
* `latest` - the latest release will be installed. Subsequent converges
  will always re-install even if chef is present.
* `<VERSION_STRING>` (ex: `10.24.0`) - the desired version string will
  be passed the the install.sh script. Subsequent converges will skip if
  the installed version and the desired version match.
* `false` or `nil` - no chef is installed.

The default value is unset, or `nil`.

## <a name="development"></a> Development

* Source hosted at [GitHub][repo]
* Report issues/questions/feature requests on [GitHub Issues][issues]

Pull requests are very welcome! Make sure your patches are well tested.
Ideally create a topic branch for every separate change you make. For
example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## <a name="authors"></a> Authors

Created and maintained by [Jeff Moody][author] (<fifthecho@gmail.com>)

## <a name="license"></a> License

Apache 2.0 (see [LICENSE][license])


[author]:           https://github.com/fifthecho
[issues]:           https://github.com/test-kitchen/kitchen-cloudstack/issues
[license]:          https://github.com/test-kitchen/kitchen-cloudstack/blob/master/LICENSE
[repo]:             https://github.com/test-kitchen/kitchen-cloudstack
[driver_usage]:     http://docs.kitchen-ci.org/drivers/usage
[chef_omnibus_dl]:  http://getchef.com/chef/install/
