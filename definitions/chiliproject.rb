require 'yaml'

define :chiliproject, :name => "default", :instance => {} do
  inst = params[:instance]

  deploy_to = "#{node['chiliproject']['root_dir']}/#{inst['id']}"

  chili_user = "chili_#{inst['id'].downcase.gsub(/[^a-z]/, '_')}"
  chili_group = chili_user

  rails_env = inst['rails_env']
  rails_env ||= (node.chef_environment =~ /_default/ ? 'production' :  node.chef_environment)
  node.run_state[:rails_env] = rails_env

  # Reset the list of additional files to symlink before migration
  node.run_state[:chiliproject_deploy_symlinks] = {}

  #############################################################################
  # Install package dependencies

  gem_package "bundler" do
    action :install
    version ">= 1.0.14" # minimal version for ChiliProject
  end

  #############################################################################
  # Users and Groups

  # Create the user and group, one for each instance
  group chili_group
  user chili_user do
    comment 'ChiliProject'
    gid chili_group
    home deploy_to
    system true
    shell '/bin/bash'
  end

  # Create a shared group containing all the users of each instance
  # Use for shared files to ensure minimal permissions
  group "chiliproject" do
    members chili_user
    append true
  end

  #############################################################################
  # Basic Directory Structure

  [deploy_to, "#{deploy_to}/shared"].each do |dir|
    directory dir do
      owner chili_user
      group chili_group
      mode '0755'
      recursive true
    end
  end

  %w[logs pids system vendor/bundle].each do |dir|
    directory "#{deploy_to}/shared/#{dir}" do
      owner chili_user
      group chili_group
      mode '0750'
      recursive true
    end
  end

  # Shared directory for uploaded files, repositories, ...
  directory node['chiliproject']['shared_dir'] do
    owner 'root'
    group 'root'
    mode '0755'
    recursive true
  end
  directory "#{node['chiliproject']['shared_dir']}/#{inst['id']}" do
    owner 'root'
    group 'root'
    mode '0755'
  end

  # Uploaded attachments
  directory "#{node['chiliproject']['shared_dir']}/#{inst['id']}/files" do
    owner chili_user
    group chili_group
    mode "2750"
  end

  # Log files
  directory node['chiliproject']['log_dir'] do
    owner 'root'
    group 'root'
    mode '0755'
    recursive true
  end
  directory "#{node['chiliproject']['log_dir']}/#{inst['id']}" do
    owner chili_user
    group chili_group
    mode '0750'
  end
  file "#{node['chiliproject']['log_dir']}/#{inst['id']}/#{rails_env}.log" do
    action :create_if_missing
    owner chili_user
    group chili_group
    mode '0640'
    content "# Logfile created on #{Time.now.to_s}"
  end

  #############################################################################
  # Session configuration

  session_config = {
    'key' => "_chili_#{inst['id']}_session",
    'session_path' => base_uri(inst).path || "/"
  }
  session_config['secure'] = true if base_uri(inst).scheme == "https"
  session_config.merge!(inst['session'])
  template "#{deploy_to}/shared/session_store.rb" do
    source "session_store.rb.erb"
    owner chili_user
    group chili_group
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
  configuration_default['autologin_cookie_path'] ||= base_uri(inst).path || "/"
  unless configuration_default.has_key?("autologin_cookie_secure")
    configuration_default['autologin_cookie_secure'] = true if base_uri(inst).scheme == "https"
  end

  configuration_production = {'email_delivery' => {}}
  configuration_production['email_delivery'].tap do |cfg|
    node_cfg = node['chiliproject']['email_delivery']
    inst_cfg = inst['email_delivery']

    cfg['delivery_method'] = :async_smtp
    cfg['smtp_settings'] = {
      'address' => get_hosts('email_delivery').first.ipaddress,
      'port' => inst_cfg['port'] || node_cfg['port'],
      'domain' => node['fqdn'],
    }
    if (login = inst_cfg.has_key?('login') ? inst_cfg['login'] : node_cfg['login'])
      cfg['smtp_settings'].merge!({
        'login' => login,
        "user_name" => inst_cfg['user_name'] || node_cfg['user_name'],
        "user_name" => inst_cfg['password'] || node_cfg['password']
      })
    end
  end

  configuration_development = {'email_delivery' => {}}
  configuration_development['email_delivery'].tap do |cfg|
    cfg['delivery_method'] = :smtp
    cfg['smtp_settings'] = configuration_production['email_delivery']['smtp_settings'].dup
  end

  configuration_test = {'email_delivery' => {'delivery_method' => 'test'}}

  prod_env = ['test', 'development'].include?(rails_env) ? 'production' : rails_env
  configuration = {
    'default' => configuration_default,
    prod_env => configuration_production,
    'development' => configuration_development,
    'test' => configuration_test
  }

  file "#{deploy_to}/shared/configuration.yml" do
    owner chili_user
    group chili_group
    mode '0400'
    content configuration.to_yaml
  end

  #############################################################################
  # database.yml

  # Get the merged config hash from node and instance
  db = db_hash(inst)

  # generate additional config for SSL connectivity
  if db_hash_for_database_yml.delete(:ssl)
    # TODO: setup SSL for database connectivity
  end
  # Cleanup internal keys
  db_hash_for_database_yml = db.reject do |k, v|
    %w[create_if_missing backup_before_migration].include?(k.to_s)
  end

  database_yml = {rails_env => db_hash_for_database_yml}
  unless database_yml.has_key?('development')
    database_yml['development'] = db_hash_for_database_yml
  end

  file "#{deploy_to}/shared/database.yml" do
    owner chili_user
    group chili_group
    mode '0400'
    content db_hash_for_database_yml.to_yaml
  end

  if db['backup_before_migration']
    # Prepare the database backup before the migration if configured
    case db['adapter']
    when "mysql2"
      template "#{deploy_to}/shared/database_backup.cnf" do
        source "database_backup.cnf.erb"
        owner chili_user
        group chili_group
        mode '0400'
        variables :db => db
      end
    when "postgresql"
      template "#{deploy_to}/.pg_pass" do
        source "pgpass.erb"
        owner chili_user
        group chili_group
        mode '0400'
        variables :db => db
      end
    end

    backup_dir = "#{node['chiliproject']['shared_dir']}/#{inst['id']}/backup"
    directory backup_dir do
      owner chili_user
      group chili_group
      mode "2750"
      recursive true
    end
  end

  #############################################################################
  # Additional environment

  memcached_hosts = get_hosts('memcached')
  if memcached_hosts && !memcached_hosts.empty?
    memcached_hosts = memcached_hosts.collect do |node|
      ip = node['ipaddress']
      ip += ":#{node['memcached']['port']}" if node['memcached']['port']
      ip
    end
  else
    memcached_hosts = nil
  end
  template "#{deploy_to}/shared/additional_environment.rb" do
    source "additional_environment.rb.erb"
    owner chili_user
    group chili_group
    mode "0440"
    variables :name => inst['id'], :memcached_hosts => memcached_hosts
  end

  # Setup a .rvmrc to enforce the current gemset throughout the wholelife of
  # the instance (if applicable)
  chiliproject_rvmrc inst['id']

  #############################################################################
  # Now do the actual application deployment.
  # The fun starts here :)

  chiliproject_deploy_key inst['id'] do
    instance inst
  end

  deploy_target = deploy_to
  deploy_revision "ChiliProject #{inst['id']}" do
    repository inst['repository'] || "https://github.com/chiliproject/chiliproject.git"
    revision inst['revision'] || "stable"

    user chili_user
    group chili_group

    deploy_to deploy_target
    environment 'RAILS_ENV' => rails_env, 'RACK_ENV' => rails_env

    action inst['force_deploy'] ? :force_deploy : :deploy
    ssh_wrapper "#{app['deploy_to']}/deploy-ssh-wrapper" if inst['deploy_key']
    shallow_clone true

    if (inst.has_key?('migrate') ? inst['migrate'] : node['chiliproject']['migrate'])
      migrate true
      migration_command "bundle exec rake db:migrate db:migrate:plugins --trace"
    else
      migrate false
    end

    ignored_groups = inst['ignored_bundler_groups'] || []
    before_migrate do
      #########################################################################
      # Select the bundler groups and install them

      common_groups = %w[development test production]
      database_groups = %w[mysql mysql2 postgres sqlite]

      ignored_groups += (common_groups - [rails_env])
      adapter_group = case db['adapter'].downcase
        when 'postgresql' then "postgres"
        when "sqlite3" then "sqlite"
        else db['adapter'].downcase
      end
      ignored_groups += (database_groups - [adapter_group])

      unless ignored_groups.include? "rmagick"
        include_recipe "imagemagick::rmagick"
      end

      deployment_flag = File.exists?("#{deploy_target}/Gemfile.lock") ? "--deployment" : ""
      execute "bundle install #{deployment_flag} --without #{ignored_groups.join(' ')}" do
        cwd release_path
        user 'root'
        group 'root'
      end

      #########################################################################
      # Backup existing databases before migration

      if (inst.has_key('migrate') ? inst['migrate'] : node['chiliproject']['migrate']) &&
        (inst.has_key('backup_before_migration') ? inst['backup_before_migration'] : node['chiliproject']['database']['backup_before_migration'])

        case db['adapter']
        when "mysql2"
          target_file = backup_dir + "/mysql-#{Time.now.strftime("%Y%m%dT%H%M%S")}-#{release_slug}.sql.gz"

          args = []
          args << "--defaults-extra-file='#{deploy_to}/shared/database_backup.cnf'"
          args << "--single-transaction"
          args << "--quick"
          args << "--no-create-db"
          args << "--databases '#{db['database']}'"

          execute "mysqldump #{args.join(" ")} | gzip > '#{target_file}'" do
            user chili_user
            group chili_group
          end
        when "postgresql"
          target_file = backup_dir + "/postgresql-#{Time.now.strftime("%Y%m%dT%H%M%S")}-#{release_slug}.sql.gz"

          args = []
          args << "--host '#{db['host']}'"
          args << "--port '#{db['port']}'"
          args << "--username '#{db['username']}'"
          args << "--no-password"
          args << "--format custom"
          args << "--file '#{target_file}'"
          args << "'#{db['database']}'"

          execute "pg_dump #{args.join(" ")}" do
            user chili_user
            group chili_user
          end
        when "sqlite3"
          target_file = backup_dir + "/postgresql-#{Time.now.strftime("%Y%m%dT%H%M%S")}-#{release_slug}.sqlite"

          ruby_block "Backup Sqlite3 DB for #{inst['id']}" do
            block do
              FileUtils::copy_file(db['database'], target_file)
            end
            action :create
          end
        end
      end
    end

    symlink_before_migrate({
      "database.yml" => "config/database.yml",
      "configuration.yml" => "config/configuration.yml",
      "session_store.rb" => "config/initializers/session_store.rb",
      "additional_environment.rb" => "config/additional_environment.rb"
    })
    symlink_before_migrate.merge! node.run_state[:chiliproject_deploy_symlinks]
  end

  #############################################################################
  # Finally setup logrotate for the logfiles

  if node['chiliproject']['logrotate']
    logrotate_app "ChiliProject #{inst['id']}" do
      cookbook "chiliproject"
      path "#{node['chiliproject']['log_dir']}/#{inst['id']}/*.log"
      frequence "weekly"
      rotate 8
      create "640 #{chili_user} #{chili_group}"
    end
  end
end
