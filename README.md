# <a name="title">Kitchen::CloudStack</a>

A Test Kitchen Driver for Apache CloudStack / Citrix CloudPlatform.

## <a name="requirements">Requirements</a>

This Gem only requires FOG of a version greater than 1.3.1. However, as most of your knife plugins will be using newer
versions of FOG, that shouldn't be an issue.

## <a name="installation"></a> Installation and Setup

Please read the [Driver usage][driver_usage] page for more details.

## <a name="config">Configuration</a>

Provide, at a minimum, the required driver options in your `.kitchen.yml` file:

    driver_plugin: cloudstack
    driver_config:
      cloudstack_api_key: [YOUR CLOUDSTACK API KEY]
      cloudstack_secret_key: [YOUR CLOUDSTACK SECRET KEY]
      cloudstack_api_url: [YOUR CLOUDSTACK API URL]
      require_chef_omnibus: latest (if you'll be using Chef)
      template_id: [INSTANCE TEMPLATE ID]
      serviceoffering_id: [INSTANCE SERVICE OFFERING ID]
      zone_id: [INSTANCE ZONE ID]

By default, a unique server name will be generated and the randomly generated password will be used, though that
behavior can be overridden with additional options (e.g., to specify a SSH private key):

    name: [A UNIQUE SERVER NAME]
    public_key_path: [PATH TO YOUR SSH PUBLIC KEY]
    username: [SSH USER]
    port: [SSH PORT]

Only disable SSL cert validation if you absolutely know what you are doing,
but are stuck with an OpenStack deployment without valid SSL certs.

    disable_ssl_validation: true

### <a name="config-require-chef-omnibus">require\_chef\_omnibus</a>

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

## <a name="development">Development</a>

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

## <a name="authors">Authors</a>

Created and maintained by [Jeff Moody][author] (<fifthecho@gmail.com>)

## <a name="license"></a> License

Apache 2.0 (see [LICENSE][license])


[author]:           https://github.com/fifthecho
[issues]:           https://github.com/fifthecho/kitchen-cloudstack/issues
[license]:          https://github.com/fifthecho/kitchen-cloudstack/blob/master/LICENSE
[repo]:             https://github.com/fifthecho/kitchen-cloudstack
[driver_usage]:     http://docs.kitchen-ci.org/drivers/usage
[chef_omnibus_dl]:  http://www.opscode.com/chef/install/
