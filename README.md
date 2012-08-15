# Chef Cookbook for ChiliProject

This cookbook helps you to deploy one or more Chiliproject instances. Right now, it supports only a pre-packed ChiliProject source repository. That means if you require any additional plugins, you have to put them into your source repository before installing it here.

We support MySQL, Postgres and SQLite3 as a database. You can mix and match the database engines between instances.

All of the requirements are explicitly defined in the recipes. Every effort has been made to utilize official Opscode cookbooks.

This cookbook requires Chef >= 10.12.0. See *Known Issues* for details

# Attributes

## Basic paths

Define basic paths. By default, these paths define the parent directories for certain parts of ChiliProject. If not overwritten in instances, a sub directory will be created in these directories for each instance.

All of these paths can be overwritten in instance databags.

* `node[:chiliproject][:root_dir]` = The root directory where all instances are installed to. For each instance there will be one sub directory. To overwrite this in an instance, set `deploy_to`
* `node[:chiliproject][:shared_dir]` - The directory where all shared assets are installed to, this includes uploaded files and any created repositories. For each instance there will be one sub directory.
* `node[:chiliproject][:log_dir]` - The base directory where all logfiles are piped into For each instance, there will be one sub directory.

## Deployment options

This defines some general defaults for the deployment. All of these values are overwritable in instance databags.

* `node[:chiliproject][:repository]` - The repository URL to retrieve ChiliProject from. By default: `https://github.com/chiliproject/chiliproject.git`
* `node[:chiliproject][:revision]` - The revision to deploy. Can be a branch name, tag name or SHA1 hash. By default: `stable`
* `node[:chiliproject][:migrate]` - Run migrations if necessary. By default: `true`
* `node[:chiliproject][:force_deploy]` - Force a full deployment even if current revision is already deployed. By default `false`.
* `node[:chiliproject][:bundle_vendor]` - Install all gems to vendor/bundle instead of the global gem store. By default: `false`
* `node[:chiliproject][:logrotate]` - Setup logrotate. By default: `true`

## Database defaults

This is the default configuration for the database connections for all instances. Some additional keys are only practically defined on the individual instance.  All of these values are overridable in instance databags.

* `node[:chiliproject][:database][:adapter]` - Can be one of postgresql, mysql2 or sqlite3
* `node[:chiliproject][:database][:hostname]` - Use either the `hostname` or the `role`. If the role is set, it has precedence.
* `node[:chiliproject][:database][:role]`
* `node[:chiliproject][:database][:port]` - We use the default port for the chosen adapter by default
* `node[:chiliproject][:database][:encoding]` - Database encoding (default: `utf8`)
* `node[:chiliproject][:database][:collation]` - Database collation, must correspondent to the encoding (default: `en_US.utf8`)
* `node[:chiliproject][:database][:reconnect]` - Reconnect on error if true
* `node[:chiliproject][:database][:ssl]` - Set to true if the app server should connect via SSL to the database. This is a no-op currently.

* `node[:chiliproject][:database][:create_if_missing]` - Create the database and user on the server if it is missing when set to true
* `node[:chiliproject][:database][:superuser]` - These are the credentials used to create the database if required (and `create_if_missing` is set to `true`). You need to set these attributes when accessing a remote database!
* `node[:chiliproject][:database][:superuser_password]`
* `node[:chiliproject][:database][:backup_before_migrate]` - Create a full database backup before each migration. Backups are stored in `node[:chiliproject][:shared_dir]/<instance name>/backup`


## Contents of the configuration.yml

NOTE: Some attributes which are allowed in the configuration.yml file are overridden based on other config settings.
These attributes are:

* `attachments_storage_path`
* `email_delivery`

* `node[:chiliproject][:configuration]` - Set arbitrary values of the configuration.yml

## Email delivery

* `node[:chiliproject][:email_delivery][:hostname]` - Use either the `hostname` or the `role` to define the SMTP server to be used for sending mails. If the role is set, it has precedence
* `node[:chiliproject][:email_delivery][:role]`
* `node[:chiliproject][:email_delivery][:port]` - Port where the SMTP server listens.
* `node[:chiliproject][:email_delivery][:authentication]` - Login method to pass to ActionMailer. Leave as nil to completely disable SMTP authentication
* `node[:chiliproject][:email_delivery][:username]` - Username for the SMTP server when using some authentication mechanism.
* `node[:chiliproject][:email_delivery][:password]` - Password for the SMTP server when using some authentication mechanism.

## Memcached

Specify any memcached hosts which are used for caching. You can either specify direct hosts or a role. If the role is set, it has precedence before any hosts.

* `node[:chiliproject]['memcached']['hosts']` - If you specify hosts, use an array of strings containing the IP and port e.g. `["127.0.0.1:11211", "10.5.10.123:11211"]`
* `node[:chiliproject]['memcached']['role']`

## Apache

Configuration values interesting when using the `apache2` recipe. You can define defaults here which are then used for all instances unless overwritten there.

See the instance attributes for additional settable values.

* `node[:chiliproject][:apache][:document_root]` - The document root where the directories with symlinks are created for sub-path installs. This setting is irrelevant for root-path instances.
* `node[:chiliproject][:apache][:cookbook]` - The cookbook to search for a template for the Apache config
* `node[:chiliproject][:apache][:template]` - The template for the Apache config in the above cookbook.

# Instances

Instances can be configured using data bags, one for each instance. An example databag can be found in the `examples` directory. There you can define many attributes of the respective instance, some of which override the defaults set on the node.

Instance attributes have always precedence.

## Instance attributes

* `base_uri` - A URI which specifies how the instance can be reached later. You can specify the primary protocol (`http` or `https`), the port, hostname and path here. Note that nested sub-paths are not supported right now.
* `repository` - The repository URL to retrieve ChiliProject from, by default `https://github.com/chiliproject/chiliproject.git`
* `revision` - The revision to install. Can be either a SHA hash, a branch name or a tag. By default we use the `stable` branch.
* `database` - Merged with the node attributes. See the description of the node database attributes for details.
  * `database['password']` The password for connection to the database. You have to set the attribute for each instance!
  * `database['username']` - The name of the database user, defaults to `chili_<instance name>`
  * `database['database']` - The name of the database, defaults to `chili_<instance name>`
* `session` - Defines the session secret and configuration settings for the session cookie.
  * `session['secret']` - The secret key to sign session cookies with. You have to set this. It should be random ascii text unique between all instances. It should be > 50 characters.
  * `session['key']` - The name of the cookie.
  * `session['session_path']` - The path scope of the session cookie, by default the same as the instance path
* `configuration` - Set any allowed values of the configuration.yml file. Some restrictions apply. Please see the description in the node attributes section.
* `email_delivery` - Configure the settings for email delivery, i.e. how to reach the SMTP server. This overrides the default settings of the node. See there for more details.
  * `email_delivery[:hostname]` - Use either the `hostname` or the `role` to define the SMTP server to be used for sending mails. If the role is set, it has precedence
  * `email_delivery[:role]`
  * `email_delivery[:port]` - Port where the SMTP server listens.
  * `email_delivery[:authentication]` - Login method to pass to ActionMailer. Leave as nil to completely disable SMTP authentication
  * `email_delivery[:username]` - Username for the SMTP server when using some authentication mechanism.
  * `email_delivery[:password]` - Password for the SMTP server when using some authentication mechanism.
* `memcached` - The memcached hosts or role to use for caching. This overrides the default from the node. See there for details.
  * `memcached['hosts']` - An array of hosts with ports use for caching. E.g. `["127.0.0.1:11211", "10.5.10.123:11211"]`.
  * `memcached['role']` - The role so search for. If the role is set, it has precedence.
* `rails_env` - The rails environment to run with. By default `production` or the name of the chef environment.
* `force_deploy` - Force a full deployment even if the specified SHA hash is already deployed. By default `false`.
* `migrate` - Run migrations if necessary. By default `true`.
* `deploy_key` -  The private SSH key used for authenticating to the remote repository via SSH. Set this only if required.
* `netrc` -  Necessary credentials to access private repository server over HTTP. Set this only if required.
  * `netrc['hostname']` - The hostname to authenticate to, i.e. the hostname of the repository server.
  * `netrc['username']` - The username used for authenticating to the remote repository
  * `netrc['password']` - The password used for authenticating to the remote repository
* `ignored_bundler_groups` - An array of additional bundler groups to ignore. by default, we only install one database adapter and only the required environment groups.
* `apache` - Some additional configuration settings when deploying with apache
  * `apache['http_port']` - The default port used for the HTTP vhost. If the protocol of the base_uri is `http`, the port specified in the URL has precedence to this value.
  * `apache['https_port']` - The default port used for the HTTPs vhost. If the protocol of the base_uri is `https`, the port specified in the URL has precedence to this value.
  * `apache['aliases']` - Additional hostnames which are added as server aliases. Must be an array.
  * `apache['serve_aliases']` - If true, it allows the aliases to serve the page, else the canonical host from the `base_uri` is enforced.
  * `apache['ssl_certificate_file']` - The path to the SSL certificate file when using SSL.
  * `apache['ssl_key_file']` - The path to the SSL key file when using SSL.
  * `apache['ssl_ca_certificate_file']` - The path to the SSL CS certificate file when using SSL.

It should be noted that in the `apache` group, when using sub-paths, all instances configured under the same virtual host (with `base_uri`) have to share all these settings (with the exception of aliases). Thus, you need to configure these instances with the exact same values.

### Plugins

Each instance can have a number of plugins. Right now, these can be installed from either a git or a subversion repository.

Plugins are defined as part of the instance as a hash under `plugins`. The key represents the directory where the plugin is installed to. This typically **must** correspondent to the plugin name. See the individual plugin's description for details.

Each plugin can then be configured with the following attributes:

* `plugins[<plugin name>]['repository']` - The URL to the repository to retrieve the plugin from
* `plugins[<plugin name>]['revision']` - The revision to use, By default: `HEAD`
* `plugins[<plugin name>]['repository_type']` - The type of repository. Can be either `git` (default) or `subversion`
* `plugins[<plugin name>]['deploy_key']` - The private SSH key used for authenticating to the remote repository via SSH. Set this only if required.
* `plugins[<plugin name>]['netrc']` - Necessary credentials to access private repository server over HTTP. Set this only if required.
  * `plugins[<plugin name>]['netrc']['hostname']` - The hostname to authenticate to, i.e. the hostname of the repository server.
  * `plugins[<plugin name>]['netrc']['username']` - The username used for authenticating to the remote repository
  * `plugins[<plugin name>]['netrc']['password']` - The password used for authenticating to the remote repository
* `plugins[<plugin name>]['force_deploy']` - When set, overrides the respective value of the instance for this plugin only
* `plugins[<plugin name>]['callback']` - The name of a callback resource to perform additional actions

*Note:* Plugin migrations are always done together with the instance. If the instance has set `deploy` to `true` then all installed plugins are also migrated.

For most plugins, it should be sufficient to give the `repository` and `revision`. More complex plugins might require additional setup steps. These can be provided with a custom callback. This is a simple resource (e.g. an [LWRP](http://wiki.opscode.com/display/chef/Lightweight+Resources+and+Providers+%28LWRP%29) or a [Definition](http://wiki.opscode.com/display/chef/Definitions)) which accepts the following parameters:

* `name` - The name of the directory the plugin is installed to
* `instance` - The ChiliProject instance hash
* `instance_path` - The current release path of the ChiliProject instance (not the plugin)
* `plugin` - The plugin instance hash
* `action` - The name of the callback, is one of `:before_migrate`, `:before_symlink`, `:before_restart`, `:after_restart`

The callback resource is called once for each action during the respective phases of the deployment of the main instance. As we potentially need to have multiple incarnations of the resource in a single chef run, a callback *can not* be a recipe.

As an example, this is the required callback definition for the (`chiliproject_backlogs`)[https://github.com/finnlabs/chiliproject_backlogs] plugin. It runs a rake task to pull the current print label definitions at a very late stage in deployment, after all the migrations are done and all files are symlinked in place.

    define :chiliproject_backlogs do
      inst = params[:instance]
      instance_path = params[:instance_path]

      case params[:action]
      when :before_restart
        execute "bundle exec rake redmine:backlogs:current_labels --trace" do
          user inst['user']
          group inst['group']
          cwd instance_path
          environment 'RAILS_ENV' => inst['rails_env']
          ignore_failure false
        end
      end
    end

You can simply put this into the `definitions` directory of any cookbook. If the cookbook is then loaded into the `run_list` of your application server (and the callback thus be made available to the chef run), it will get picked up during deployment.

If you use a new cookbook, you also need an empty default recipe. A sample directory structure could look like this:

    my_cookbook
    |-- definitions
    |   `-- chiliproject_backlogs.rb
    |-- recipes
    |   `-- default.rb
    `-- README.md

With this in place you just need to include `recipe[my_cookbook]` into your run list and reference the definition in the `callback` attribute of your plugin.

### Additional gems and template files

Sometimes it is necessary to install additional gems and config files outside of a plugin to the application. An example is [New Relic](https://newrelic.com) which requires to install a gem and create a config file in the `config` directory. we facilitate this withoutrequiring to fork this cookbook but by merely configuring it and adding the template for the config file to another (slim) cookbook.

This facility solves rather specific use-cases. Generally, you should try to use self-contained plugins which are installed using the plugins facility described above. Plugins can require additional gems by shipping a Gemfile in their respectify root directory and thus don't need this facility at all.

You can either define additional gems and config files for all instance by adding them to the respective node-global attribute or just for single instances by adding them only to the instance. The two definitions are merged during runtime.

Additional gems can be added by extending either the `node['chiliproject']['local_gems']` of the node or the `local_gems` attribute of the instance. The key of the hash is the name of gem, the value is either `null` for installing the newest available gem, a single string for specifying the version in bundler syntax or an array of parameters for bundler.

An example for installing the newest newrelic gem for an instance is

    {
      "local_gems": {
        "newrelic_rpm": null
      }
    }

To create an additional config file, you have to do two things:

1. You have to create a cookbook which contains the template and ship it to the node.
2. You have to configure your instance to create the config file.

To create the template cookbook, you can create a new empty cookbook and put the template into the appropriate place. Most of the time, you also need to add an empty `default` recipe so you can add the cookbook to your run list and it gets pushed to the client in a chef server environment. An example layout for New Relic looks like this:

    my_cookbook
    |-- recipes
    |   `-- default.rb
    |-- templates
    |   `-- default
    |       `-- newrelic.yml.rb
    `-- README.md

The template receives a single variable, the normalized `instance` hash containing all information about the current instance. An example template for New Relic can be found [in this gist](https://gist.github.com/3362638). If you use this example, you also have to add this into your instance configuration to configure the license key:

    "newrelic_license": "deadbeefdeadbeefdeadbeef"

After you have created the template file, you have to configure your instance to actually create this file. This can be achieved by adding this to your instance config:

    {
      "config_files": {
        "newrelic.yml": {
          "source": "newrelic.yml.erb",
          "cookbook": "my_cookbook",
          "target": "config/newrelic.yml"
        }
      }
    }

While this config shows how to add a config file to a single instance, you can also configure it to be added to all instances. You can achieve this by adding the config to `node['chiliproject']['config_files']`.

The key of the configuration hash denotes the file that is created in the `shared` directory. Make sure to chose a unique name that doesn't clash with existing files. The most important attributes then denote:

* `source` - The template file in a cookbook which is used to generate the config file, by default `<name>.erb`
* `cookbook` - The cookbook where the source template is searched in, by default `chiliproject`
* `target` - The location where the file is symlinked to, relative to the instance's release path, by default `config/<name>`

Any additional values are used to override settings of the template resource. See [its documentation](http://wiki.opscode.com/display/chef/Resources#Resources-Template) for details.

# Usage

This is still a little slim. But you get the gist...

There are two recipes you need to concern yourself with:

* `default` - Installs all configured instances to the node. If configured (`node['chiliproject']['database']['create_if_missing']`) it also creates the required database and database user. If you disable this,. you have to create them before running this recipe.
* `apache2` - Sets up an Apache2 server with Passenger for hosting all the instances. This is optional and we will probably provide additional configuration options in the future (e.g nginx + passenger, nginx + thin, ...)

# Known issues

* When performing sub-path deployments, i.e., setting a `base_uri` to a URL with a path component, a bug present in Chef <= 0.10.10 prevents us from creating the required symlinks for the Apache+Passenger config. This is fixed with in [CHEF-3110](http://tickets.opscode.com/browse/CHEF-3110). Thus you need at least Chef 10.12.0 when all of these conditions apply:
  * You are using sub-path deployments
  * You are using the `chiliproject::apache2` cookbook for setting up Passenger
* For similar reasons, you need Chef >= 10.12.0 when installing plugins.
* When trying to set a database encoding which is different from the default `LC_CTYPE` with PostgreSQL, the database can not be created. The cause is [a bug in the database cookbook](http://tickets.opscode.com/browse/COOK-1401).

# License

Copyright (c) 2012 The Chiliproject Team. See [the list of contributors](https://github.com/chiliproject/cookbook/graphs/contributors) for details.

This software is licensed under the MIT license. See LICENSE for details.
