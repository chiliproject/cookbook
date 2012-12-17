require 'yaml'

# If you use this definition by yourself, make sure to pass a properly setup
# instance. You can create one using the chiliproject_instance helper from a
# databag item
#
# extend ChiliProject::Helpers
# inst = chiliproject_instance "my_instance"

define :chiliproject, :name => "default", :instance => nil do
  extend ChiliProject::Helpers

  inst = params[:instance]

  # Reset the list of additional files to symlink before migration
  # These can be amended by sub definitions
  node.run_state['chiliproject_deploy_symlinks'] = {}
  node.run_state['chiliproject_plugin_symlinks'] = {}
  node.run_state['chiliproject_plugin_callbacks'] = {}

  #############################################################################
  # Install package dependencies

  gem_package "bundler" do
    action :install
    version ">= 1.0.14" # minimal version for ChiliProject
  end

  #############################################################################
  # Users and Groups

  # Create the user and group, one for each instance
  group inst['group']
  user inst['user'] do
    comment 'ChiliProject'
    gid inst['group']
    home inst['deploy_to']
    system true
    shell '/bin/bash'
  end

  # Create a shared group containing all the users of each instance
  # Use for shared files to ensure minimal permissions
  group "chiliproject" do
    members inst['user']
    append true
  end

  #############################################################################
  # Basic Directory Structure

  [inst['deploy_to'], "#{inst['deploy_to']}/shared"].each do |dir|
    directory dir do
      owner inst['user']
      group inst['group']
      mode '0755'
      recursive true
    end
  end

  %w[pids tmp vendor vendor/bundle].each do |dir|
    directory "#{inst['deploy_to']}/shared/#{dir}" do
      owner inst['user']
      group inst['group']
      mode '0750'
      recursive true
    end
  end

  # Shared directory for uploaded files, repositories, ...
  directory inst['shared_dir'] do
    owner 'root'
    group 'root'
    mode '0755'
    recursive true
  end

  # Uploaded attachments
  directory "#{inst['shared_dir']}/files" do
    owner inst['user']
    group inst['group']
    mode "2750"
  end

  # Log files
  directory node['chiliproject']['log_dir'] do
    owner 'root'
    group 'root'
    mode '0755'
    recursive true
  end if inst['log_dir'].start_with?(node['chiliproject']['log_dir'])

  directory inst['log_dir'] do
    owner inst['user']
    group inst['group']
    mode '0750'
  end
  file "#{inst['log_dir']}/#{inst['rails_env']}.log" do
    action :create_if_missing
    owner inst['user']
    group inst['group']
    mode '0640'
    content "# Logfile created on #{Time.now.to_s}"
  end

  #############################################################################
  # Session configuration

  session_config = {
    'key' => "_chili_#{inst['id']}_session",
    'session_path' => inst['base_uri'].path
  }
  session_config['secure'] = true if inst['base_uri'].scheme == "https"
  session_config.merge!(inst['session']) if inst['session']
  template "#{inst['deploy_to']}/shared/session_store.rb" do
    source "session_store.rb.erb"
    owner inst['user']
    group inst['group']
    mode "0400"
    variables :session_config => session_config
  end

  #############################################################################
  # configuration.yml

  configuration_default = {}
  configuration_default.merge!(node['chiliproject']['configuration'] || {})
  configuration_default.merge!(inst['configuration'] || {})
  configuration_default.merge!({
    "attachments_storage_path" => "#{node['chiliproject']['shared_dir']}/#{inst['id']}/files"
  })
  # Configure the autologin cookie similar to the session cookie
  # Can be overridden in the node and instance configuration
  configuration_default['autologin_cookie_name'] ||= "_chili_#{inst['id']}_autologin"
  configuration_default['autologin_cookie_path'] ||= inst['base_uri']
  unless configuration_default.has_key?("autologin_cookie_secure")
    configuration_default['autologin_cookie_secure'] = true if inst['base_uri'].scheme == "https"
  end

  configuration_production = {'email_delivery' => {}}
  configuration_production['email_delivery'].tap do |cfg|
    node_cfg = node['chiliproject']['email_delivery'] || {}
    inst_cfg = inst['email_delivery'] || {}

    cfg['delivery_method'] = :async_smtp
    cfg['smtp_settings'] = {
      'address' => get_hosts(inst, 'email_delivery').first.ipaddress,
      'port' => inst_cfg['port'] || node_cfg['port'],
      'domain' => node['fqdn'],
      'enable_starttls_auto' => true
    }
    if (authentication = inst_cfg.has_key?('authentication') ? inst_cfg['authentication'] : node_cfg['authentication'])
      cfg['smtp_settings'].merge!({
        'authentication' => authentication.to_sym,
        "user_name" => inst_cfg['username'] || node_cfg['username'],
        "password" => inst_cfg['password'] || node_cfg['password']
      })
    end
  end

  configuration_development = {'email_delivery' => {}}
  configuration_development['email_delivery'].tap do |cfg|
    cfg['delivery_method'] = :smtp
    cfg['smtp_settings'] = configuration_production['email_delivery']['smtp_settings'].dup
  end

  configuration_test = {'email_delivery' => {'delivery_method' => 'test'}}

  prod_env = ['test', 'development'].include?(inst['rails_env']) ? 'production' : inst['rails_env']
  configuration = {
    'default' => configuration_default,
    prod_env => configuration_production,
    'development' => configuration_development,
    'test' => configuration_test
  }

  file "#{inst['deploy_to']}/shared/configuration.yml" do
    owner inst['user']
    group inst['group']
    mode '0400'
    content configuration.to_yaml
  end

  #############################################################################
  # database.yml

  # Setup SSL keys for database connectivity
  if inst['database']['ssl']
    warn("Database access via SSL is not yet supported for instance #{inst['id']}")
  end

  yaml = [inst['rails_env'], 'development'].uniq.inject({}) do |yaml, key|
    # dup to avoid anchors in the generated YAML
    yaml[key] = inst['database']['database_yml'].dup
    yaml
  end
  file "#{inst['deploy_to']}/shared/database.yml" do
    owner inst['user']
    group inst['group']
    mode '0400'
    content yaml.to_yaml
  end

  #############################################################################
  # Database backup

  if inst['database']['backup_before_migrate']
    # Prepare the database backup before the migration if configured
    case inst['database']['adapter']
    when "mysql2"
      template "#{inst['deploy_to']}/shared/database_backup.cnf" do
        source "database_backup.cnf.erb"
        owner inst['user']
        group inst['group']
        mode '0400'
        variables :db => inst['database']
      end
    when "postgresql"
      template "#{inst['deploy_to']}/.pgpass" do
        source "pgpass.erb"
        owner inst['user']
        group inst['group']
        mode '0400'
        variables :db => inst['database']
      end
    end

    backup_dir = "#{node['chiliproject']['shared_dir']}/#{inst['id']}/backup"
    directory backup_dir do
      owner inst['user']
      group inst['group']
      mode "2750"
      recursive true
    end
  end

  #############################################################################
  # Deploy helpers

  chiliproject_deploy_key "ChiliProject #{inst['id']}" do
    instance inst
  end
  chiliproject_netrc "ChiliProject #{inst['id']}" do
    instance inst
  end

  #############################################################################
  # Install plugins

  chiliproject_plugins do
    instance inst
  end

  #############################################################################
  # Setup Gemfile.local with any additional gems

  template "#{inst['deploy_to']}/shared/Gemfile.local" do
    source "Gemfile.local.erb"
    owner inst['user']
    group inst['group']
    mode "0644"
    variables :gems => inst['local_gems']
  end

  #############################################################################
  # Additional environment

  memcached_hosts = get_hosts(inst, 'memcached')
  if memcached_hosts && !memcached_hosts.empty?
    memcached_hosts = memcached_hosts.collect do |node|
      port = node['memcached']['port'] ? ":#{node['memcached']['port']}" : ""
      "#{node['ipaddress']}#{port}"
    end
  else
    memcached_hosts = nil
  end

  template "#{inst['deploy_to']}/shared/additional_environment.rb" do
    source "additional_environment.rb.erb"
    owner inst['user']
    group inst['group']
    mode "0440"
    variables :memcached_hosts => memcached_hosts, :instance => inst
  end

  #############################################################################
  # Add additional custom config files

  # If we want to override the additional_environment, we have to merge the
  # custom template with the stuff we always need to configure.
  custom_additional_environment = false

  inst['config_files'].each_pair do |name, params|
    tmpl_params = !params ? {} : params.dup

    link_target = tmpl_params.delete('target') || "config/#{name}"
    if link_target == 'config/additional_environment.rb' || name == "additional_environment.rb"
      raise "You can't override the additional_environment.rb file. Use additional_environment_custom.rb instead."
    end

    # link the resulting config file
    node.run_state['chiliproject_deploy_symlinks'][name] = link_target

    template "#{inst['deploy_to']}/shared/#{name}" do
      source tmpl_params.delete("source") || "#{name}.erb"
      cookbook tmpl_params.delete("cookbook") || "chiliproject"

      owner inst['user']
      group inst['group']
      mode tmpl_params.delete("mode") || "0644"

      variables :instance => inst
      tmpl_params.each_pair{|k, v| send(k.to_sym, v)}
    end
  end

  #############################################################################
  # Now do the actual application deployment.
  # The fun starts here :)

  # Find the bundler groups to install
  ignored_bundler_groups = inst['ignored_bundler_groups'] || []
  common_groups = %w[development test production]
  database_groups = %w[mysql mysql2 postgres sqlite]

  ignored_bundler_groups += (common_groups - [inst['rails_env']])
  adapter_group = case inst['database']['adapter']
    when 'postgresql' then "postgres"
    when "sqlite3" then "sqlite"
    else inst['database']['adapter']
  end
  ignored_bundler_groups += (database_groups - [adapter_group])

  # install rmagick requirements only if required
  include_recipe "imagemagick::rmagick" unless ignored_bundler_groups.include? "rmagick"

  deploy_revision "ChiliProject #{inst['id']}" do
    repository inst['repository'] || "https://github.com/chiliproject/chiliproject.git"
    revision inst['revision'] || "stable"

    user inst['user']
    group inst['group']

    deploy_to inst['deploy_to']
    environment 'RAILS_ENV' => inst['rails_env'], 'RACK_ENV' => inst['rails_env']

    action inst['force_deploy'] ? :force_deploy : :deploy
    ssh_wrapper "#{inst['deploy_to']}/deploy-ssh-wrapper" if inst['deploy_key']
    shallow_clone false

    if inst['migrate']
      migrate true
      migration_command "bundle exec rake db:migrate db:migrate:plugins --trace"
    else
      migrate false
    end

    before_migrate do
      #########################################################################
      # Link Gemfile.local in place
      # This must be done here as symlinks_before_migrate runs too late for
      # our bundle install
      link File.join(release_path, "Gemfile.local") do
        to "#{inst['deploy_to']}/shared/Gemfile.local"
        owner inst['user']
        group inst['group']
      end

      # Link the actual log dir into the deployed ChiliProject as
      # Rails insists of a proper logfile at its standard location
      # for its LogTailer. Man Rails 2 sucks...
      directory File.join(release_path, "log") do
        action :delete
        recursive true
      end
      link File.join(release_path, "log") do
        to inst['log_dir']
        owner inst['user']
        group inst['group']
      end

      #########################################################################
      # Link the plugins into place

      # We have to do this by hand as it's too late for bundle install when
      # using symlink_before_migrate
      node.run_state['chiliproject_plugin_symlinks'].each_pair do |source, target|
        link File.join(release_path, target) do
          to source
          owner inst['user']
          group inst['group']
        end
      end

      directory "#{release_path}/public/plugin_assets" do
        owner inst['user']
        group inst['group']
        mode 0755
      end

      #########################################################################
      # Select the bundler groups and install them

      deployment_flag = ''
      deployment_flag << " --deployment" if File.exists?("#{inst['deploy_to']}/Gemfile.lock")
      deployment_flag << " --path vendor/bundle" if inst['bundle_vendor']
      if deployment_flag != ""
        execute "bundle install #{deployment_flag} --without #{ignored_bundler_groups.join(' ')}" do
          cwd release_path
          user inst['user']
          group inst['group']
        end
      else
        execute "bundle install --without #{ignored_bundler_groups.join(' ')}" do
          cwd release_path
          user 'root'
          group 'root'
        end
      end

      #########################################################################
      # Backup existing databases before migration

      if inst['migrate'] && inst['database']['backup_before_migrate']
        case inst['database']['adapter']
        when "mysql2"
          target_file = backup_dir + "/mysql-#{Time.now.strftime("%Y%m%dT%H%M%S")}-#{release_slug}.sql.gz"

          args = []
          args << "--defaults-extra-file='#{inst['deploy_to']}/shared/database_backup.cnf'"
          args << "--single-transaction"
          args << "--quick"
          args << "--no-create-db"
          args << "--databases '#{inst['database']['database']}'"

          execute "mysqldump #{args.join(" ")} | gzip > '#{target_file}'" do
            user inst['user']
            group inst['group']
          end
        when "postgresql"
          target_file = backup_dir + "/postgresql-#{Time.now.strftime("%Y%m%dT%H%M%S")}-#{release_slug}.sql.gz"

          args = []
          args << "--host '#{inst['database']['host']}'"
          args << "--port '#{inst['database']['port']}'"
          args << "--username '#{inst['database']['username']}'"
          args << "--no-password"
          args << "--format custom"
          args << "--file '#{target_file}'"
          args << "'#{inst['database']['database']}'"

          execute "pg_dump #{args.join(" ")}" do
            user inst['user']
            group inst['group']
          end
        when "sqlite3"
          target_file = backup_dir + "/sqlite-#{Time.now.strftime("%Y%m%dT%H%M%S")}-#{release_slug}.sqlite"

          ruby_block "Backup Sqlite3 DB for #{inst['id']}" do
            block do
              FileUtils::copy_file(inst['database']['database'], target_file)
            end
            only_if { File.exist?(inst['database']['database']) }
            action :create
          end
        end
      end

      current_release = release_path
      node.run_state['chiliproject_plugin_callbacks'].each do |name, info|
        send(info['callback'], name) do
          action :before_migrate
          instance inst
          plugin info['plugin']
          instance_path current_release
        end
      end
    end

    symlink_before_migrate({
      "database.yml" => "config/database.yml",
      "configuration.yml" => "config/configuration.yml",
      "session_store.rb" => "config/initializers/session_store.rb",
      "additional_environment.rb" => "config/additional_environment.rb"
    })
    symlink_before_migrate.merge! node.run_state['chiliproject_deploy_symlinks']

    %w[before_symlink before_restart after_restart].each do |cb|
      send(cb.to_sym) do
        current_release = release_path
        node.run_state['chiliproject_plugin_callbacks'].each do |name, info|
          send(info['callback'], name) do
            action cb.to_sym
            instance inst
            plugin info['plugin']
            instance_path current_release
          end
        end
      end
    end
  end

  #############################################################################
  # Setup logrotate for the logfiles

  if inst['logrotate']
    logrotate_app "ChiliProject #{inst['id']}" do
      path "#{inst['log_dir']}/*.log"
      frequence "weekly"
      rotate 8
      create "640 #{inst['user']} #{inst['group']}"
    end
  end

  #############################################################################
  # Enforce the default settings into the database

  unless inst['settings'].empty?
    chiliproject_settings "Enforce instance settings for #{inst['id']}" do
      values inst['settings']
      instance inst
    end
  end
end
