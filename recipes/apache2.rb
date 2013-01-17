extend ChiliProject::Helpers

include_recipe "chiliproject"

include_recipe "apache2"
include_recipe "apache2::mod_rewrite"
include_recipe "passenger_apache2::mod_rails"

vhosts = {}
instances_to_restart = []

##########################################################################
# 1. Match the instances to vhosts. We use the base_uri parameter here

data_bag(node["chiliproject"]["databag"]).each do |name|
  inst = chiliproject_instance(name)

  vhosts[inst['base_uri'].host] ||= {}
  vhosts[inst['base_uri'].host][inst['base_uri'].path] = inst

  if vhosts[inst['base_uri'].host].keys.include?("/") && vhosts[inst['base_uri'].host].keys.count > 1
    raise "I can only deploy either one instances at the root path or multiple at sub-paths"
  end

  include_recipe "apache2::mod_ssl" if inst['base_uri'].scheme == "https"

  webhost_uri  = inst['external_uri'].host
  webhost_uri += ":#{inst['external_uri'].port}" unless inst['external_uri'].port == inst['external_uri'].default_port
  webhost_uri += inst['external_uri'].path unless inst['external_uri'].path == "/"

  chiliproject_settings "Set hostname for #{inst['id']}" do
    values "host_name" => webhost_uri,
           "protocol" => inst['external_uri'].scheme
    instance inst
  end

  unless inst['repository_hosting'].empty?
    include_recipe "chiliproject::chiliproject_pm"

    if !inst['sys_key'] || inst['sys_key'].empty?
      raise "You have to configure a sys_key to use repository hosting for ChiliProject instance #{inst['id']}."
    end

    chiliproject_settings "Enable SYS API for #{inst['id']}" do
      values "sys_api_key" => inst['sys_key'],
             "sys_api_enabled" => 1
      instance inst
    end

    group "#{inst['group']}_repo" do
      members [inst['user'], node['apache']['user']]
    end

    directory "#{node['chiliproject']['shared_dir']}/#{inst['id']}" do
      owner 'root'
      group 'root'
      mode '0755'
      recursive true
    end

    ##########################################################################
    # Hosted Git repopsitories
    if inst['repository_hosting'].include?('git')
      include_recipe "apache2::mod_cgi"
      include_recipe "apache2::mod_alias"
      include_recipe "apache2::mod_env"

      directory "#{node['chiliproject']['shared_dir']}/#{inst['id']}/git" do
        owner node['apache']['user']
        group "#{inst['group']}_repo"
        mode '2750'
      end
    end

    ##########################################################################
    # Hosted Subversion repositories
    if inst['repository_hosting'].include?('subversion')
      include_recipe "subversion::client"
      include_recipe "apache2::mod_dav_svn"

      directory "#{node['chiliproject']['shared_dir']}/#{inst['id']}/svn" do
        owner node['apache']['user']
        group "#{inst['group']}_repo"
        mode '2750'
      end
    end
  end
end

##########################################################################
# 2. For the matched vhosts, generate the apache config

vhosts.each_pair do |hostname, paths|
  aliases = [node['fqdn']]
  aliases += paths.values.collect{|inst| inst['id'] + (node['domain'] ? ".#{node['domain']}" : "") }
  aliases << node['cloud']['public_hostname'] if node.has_key?("cloud")

  if paths.keys == ["/"]
    ##########################################################################
    # We have a vhost with a single instance on the root path

    inst = paths["/"]
    aliases += inst['apache']['aliases'] if inst['apache']['aliases']
    aliases = aliases.flatten.uniq.compact

    web_app hostname do
      docroot "#{inst['deploy_to']}/current/public"

      server_name hostname
      server_aliases aliases
      log_dir node['apache']['log_dir']

      passenger_paths paths

      http_port  (inst['base_uri'].scheme == "http"  && inst['base_uri'].port) || inst['apache']['http_port']  || "80"
      https_port (inst['base_uri'].scheme == "https" && inst['base_uri'].port) || inst['apache']['https_port'] || "443"
      ssl (inst['base_uri'].scheme == "https")
      force_ssl (inst['external_uri'].scheme == "https")
      ssl_certificate_file inst['apache']['ssl_certificate_file']
      ssl_key_file inst['apache']['ssl_key_file']
      ssl_ca_certificate_file inst['apache']['ssl_ca_certificate_file']

      serve_aliases inst['apache']['serve_aliases']

      template node['chiliproject']['apache']['template']
      cookbook node['chiliproject']['apache']['cookbook']
    end

    instances_to_restart << inst
  else
    ##########################################################################
    # We have a vhost with multiple instances on subpaths

    apache_docroot = node['chiliproject']['apache']['docroot'] + "/#{hostname}"
    directory apache_docroot do
      owner "root"
      group node['apache']['group']
      mode "0755"
      recursive true
    end

    web_app_params = {}
    paths.each_pair do |path, inst|
      aliases += [inst['apache']['aliases']] if inst['apache']['aliases']

      link "#{apache_docroot}#{inst['base_uri'].path}" do
        to "#{inst['deploy_to']}/current/public"
        owner inst['user']
        group inst['group']
      end

      protocol_settings = {}
      protocol_settings['force_ssl'] = (inst['external_uri'].scheme == "https")
      if inst['base_uri'].scheme == "http"
        protocol_settings['http_port'] = inst['base_uri'].port
        protocol_settings['https_port'] = inst['apache']['https_port'] || "443"
        protocol_settings['ssl'] = false
      elsif inst['base_uri'].scheme == "https"
        protocol_settings['http_port'] = inst['apache']['http_port'] || "80"
        protocol_settings['https_port'] = inst['base_uri'].port
        protocol_settings['ssl'] = true
      else
        raise "Unexpected protocol in base_uri for ChiliProject #{inst['id']}"
      end

      %w[http_port https_port ssl force_ssl].each do |key|
        if web_app_params[key].nil? || web_app_params[keys] == protocol_settings[key]
          web_app_params[key] = protocol_settings[key]
        else
          raise "Two or more ChiliProject sub path instances differ in their effective #{key} value"
        end
      end

      %w(ssl_certificate_file ssl_key_file ssl_ca_certificate_file serve_aliases template cookbook).each do |key|
        if web_app_params[key].nil? || web_app_params[keys] == inst['apache'][key]
          web_app_params[key] = inst['apache'][key]
        else
          raise "Two or more ChiliProject sub path instances have different #{key} keys"
        end
      end

      instances_to_restart << inst
    end

    web_app hostname do
      docroot apache_docroot
      server_name hostname
      server_aliases aliases.flatten.uniq.compact
      log_dir node['apache']['log_dir']

      passenger_paths paths

      web_app_params.each_pair do |k, v|
        send(k, v)
      end
    end
  end

  # Force the file mode if the vhost to be more restrictive than default to
  # protect the API key.
  t = resources(:template => "#{node['apache']['dir']}/sites-available/#{hostname}.conf")
  t.mode "0640"
end

##########################################################################
# 3. Disable the default Apache vhost

apache_site "000-default" do
  enable !vhosts.any?
end

##########################################################################
# 4. restart instances if necessary

instances_to_restart.uniq.each do |inst|
  if File.exists?("#{inst['deploy_to']}/current")
    d = resources(:deploy_revision => "ChiliProject #{inst['id']}")
    d.restart_command "touch \"#{d.deploy_to}/current/tmp/restart.txt\""
  end
end
