##############################################################################
# Basic paths

# The root directory where all instances are installed to.
# For each instance there will be one sub directory.
default['chiliproject']['root_dir'] = "/opt/chiliproject"

# The directory where all shared assets are installed to, this includes
# uploaded files and any created repositories.
# By default, there there will be one sub directory for each instance.
# This value can be overwritten in instance databags.
default['chiliproject']['shared_dir'] = "/opt/chiliproject/shared"

# The base directory where all logfiles are piped into
# By default, there there will be one sub directory for each instance.
# This value can be overwritten in instance databags.
default['chiliproject']['log_dir'] = "/var/log/chiliproject"


##############################################################################
# Deployment options
# All of these values are overridable in instance databags

# The repository URL to retrieve ChiliProject from
default['chiliproject']['repository'] = "https://github.com/chiliproject/chiliproject.git"
# The revision to deploy. Can be a branch name, tag name or SHA1 hash
default['chiliproject']['revision'] = "stable"
# Run migrations if necessary
default['chiliproject']['migrate'] = true
# Force a full deployment even if current revision is already deployed if true
default['chiliproject']['force_deploy'] = false
# Install all gems to vendor/bundle instead of the global gem store
default['chiliproject']['bundle_vendor'] = false


# Setup logrotate if true
default['chiliproject']['logrotate'] = true

##############################################################################
# Default configuration for the database connections for all instances
# All of these values are overridable in instance databags

# Can be one of postgresql, mysql2 or sqlite3
default['chiliproject']['database']['adapter'] = "postgresql"
# Use either the hostname or the role, if the role is set, it has precedence.
default['chiliproject']['database']['hostname'] = "localhost"
default['chiliproject']['database']['role'] = nil
# We use the default port for the chosen adapter by default
default['chiliproject']['database']['port'] = nil
default['chiliproject']['database']['encoding'] = "utf8"
default['chiliproject']['database']['collation'] = "en_US.utf8"
default['chiliproject']['database']['reconnect'] = true
# Don't connect to the database via SSL by default
# This option is still a no-op
default['chiliproject']['database']['ssl'] = false

# Create the database and user on the server if it is missing
default['chiliproject']['database']['create_if_missing'] = true
# These are the credentials used to create the database if required
# If not set, the defaults from the database cookbook are used for each DB type
default['chiliproject']['database']['superuser'] = nil
default['chiliproject']['database']['superuser_password'] = nil

# Create a full database backup before each migration
default['chiliproject']['database']['backup_before_migrate'] = true


##############################################################################
# Contents of the configuration.yml
#
# NOTE: Some attributes are overridden based on other config settings
# These are:
#   attachments_storage_path
#   email_delivery

default['chiliproject']['configuration'] = {}

# Use either the hostname or the role, if the role is set, it has precedence
default['chiliproject']['email_delivery']['hostname'] = "localhost"
default['chiliproject']['email_delivery']['role'] = nil
default['chiliproject']['email_delivery']['port'] = 25
# Login method to pass to ActionMailer
# Leave as nil to completely disable SMTP authentication
default['chiliproject']['email_delivery']['login'] = nil
default['chiliproject']['email_delivery']['username'] = nil
default['chiliproject']['email_delivery']['password'] = nil

##############################################################################
# Memcached

# If you specify hosts, use an array of strings containing the IP and port
# e.g. ["127.0.0.1:11211", "10.5.10.123:11211"]
# If the role is set, it has precedence before any hosts.
default['chiliproject']['memcached']['hosts'] = []
default['chiliproject']['memcached']['role'] = nil

##############################################################################
# Apache

# The docroot where the directories with symlinks are created for sub-path
# installs. This setting is irrelevant for root-path instances
default['chiliproject']['apache']['document_root'] = "/var/www"

# Where to search for a template for the Apache config
default['chiliproject']['apache']['cookbook'] = "chiliproject"
default['chiliproject']['apache']['template'] = "apache.conf.erb"
