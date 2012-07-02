# Chef Cookbook for ChiliProject

This cookbook helps you to deploy one or more Chiliproject instances. Right now, it supports only a pre-packed ChiliProject source repository. That means if you require any additional plugins, you have to put them into your source repository before installing it here.

We support MySQL, Postgres and SQLite3 as a database. You can mix and match the database engines between instances.

All of the requirements are explicitly defined in the recipes. Every effort has been made to utilize official Opscode cookbooks.

This cookbook requires Chef >= 10.12.0. See *Known Issues* for details

# Attributes

## Basic paths

* `node[:chiliproject][:root_dir]` = The root directory where all instances are installed to. For each instance there will be one sub directory.
* `node[:chiliproject][:shared_dir]` - The directory where all shared assets are installed to, this includes uploaded files and any created repositories. For each instance there will be one sub directory.
* `node[:chiliproject][:log_dir]` - The base directory where all logfiles are piped into For each instance, there will be one sub directory.
* `node[:chiliproject][:logrotate]` - Setup logrotate if true

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
* `node[:chiliproject][:database][:backup_before_migration]` - Create a full database backup before each migration. Backups are stored in `node[:chiliproject][:shared_dir]/<instance name>/backup`


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
* `node[:chiliproject][:email_delivery][:login]` - Login method to pass to ActionMailer. Leave as nil to completely disable SMTP authentication
* `node[:chiliproject][:email_delivery][:username]` - Username for the SMTP server when using some authentication mechanism.
* `node[:chiliproject][:email_delivery][:password]` - Password for the SMTP server when using some authentication mechanism.

## Memcached

Specify any memcached hosts which are used for caching. You can either specify direct hosts or a role. If the role is set, it has precedence before any hosts.

* `node[:chiliproject]['memcached']['hosts']` - If you specify hosts, use an array of strings containing the IP and port e.g. `["127.0.0.1:11211", "10.5.10.123:11211"]`
* `node[:chiliproject]['memcached']['role']`

## Apache

* `node[:chiliproject][:apache][:docroot]` - The docroot where the directories with symlinks are created for sub-path installs. This setting is irrelevant for root-path instances.
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
  * `email_delivery[:login]` - Login method to pass to ActionMailer. Leave as nil to completely disable SMTP authentication
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
  * `apache['http_port']` - Overwrite the port used for the HTTP vhost.
  * `apache['https_port']` - Overwrite the port used for the HTTPs vhost.
  * `apache['aliases']` - Additional hostnames which are added as server aliases. Must be an array.
  * `apache['serve_aliases']` - If true, it allows the aliases to serve the page, else the cannonical host from the base_uri is enforced.
  * `apache['ssl_certificate_file']` - The path to the SSL certificate file when using SSL.
  * `apache['ssl_key_file']` - The path to the SSL key file when using SSL.
  * `apache['ssl_ca_certificate_file']` - The path to the SSL CS certificate file when using SSL.

It should be noted that in the `apache` group, when using sub-paths, all instances configured under the same virtual host (with `base_uri`) have to share all these settings (with the exception of aliases). Thus, you need to configure these instances with the exact same values.

# Usage

This is still a little slim. But you get the gist...

There are two recipes you need to concern yourself with:

* `default` - Installs all configured instances to the node. If configured (`node['chiliproject']['database']['create_if_missing']`) it also creates the required database and database user. If you disable this,. you have to create them before running this recipe.
* `apache2` - Sets up an Apache2 server with Passenger for hosting all the instances. This is optional and we will probably provide additional configuration options in the future (e.g nginx + passenger, nginx + thin, ...)

# Known issues

* When performing sub-path deployments, i.e., setting a `base_uri` to a URL with a path component, a bug present in Chef <= 0.10.10 prevents us from creating the required symlinks for the Apache+Passenger config. This is fixed with in [CHEF-3110](http://tickets.opscode.com/browse/CHEF-3110). Thus you need at least Chef 10.12.0 when all of these conditions apply:
  * You are using sub-path deployments
  * You are using the `chiliproject::apache2` cookbook for setting up Passenger
* When trying to set a database encoding which is different from the default `LC_CTYPE` with PostgreSQL, the database can not be created. The cause is [a bug in the database cookbook](http://tickets.opscode.com/browse/COOK-1401).

# License

GPLv2 for now. But this might change too...
