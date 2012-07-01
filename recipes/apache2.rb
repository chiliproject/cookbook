self.class.send(:include, ChiliProject::Helpers)

include_recipe "apache2"
include_recipe "apache2::mod_rewrite"
include_recipe "passenger_apache2::mod_rails"

instances = Chef::DataBag.load("chiliproject").values

vhosts = {}
instances_to_restart = []

##########################################################################
# 1. Match the instances to vhosts. We use the base_uri parameter here

instances.each do |inst|
  uri = base_uri(inst)

  vhosts[uri.host] ||= {}
  vhosts[uri.host][uri.path] = inst

  if vhosts[uri.host].keys.include?("/") && vhosts[uri.host].keys.count > 1
    raise "I can only deploy either one instances at the root path or multiple at sub-paths"
  end

  include_recipe "apache2::mod_ssl" if uri.scheme == "https"
end


##########################################################################
# 2. For the matched vhosts, generate the apache config

vhosts.each_pair do |hostname, paths|
  aliases = [
    "#{inst['id']}.#{node['domain']}",
    node['fqdn'],
  ]
  aliases << node['cloud']['public_hostname'] if node.has_key?("cloud")

  if paths.keys == ["/"]
    ##########################################################################
    # We have a vhost with a single instance on the root path

    inst = paths["/"]

    aliases += inst['apache']['aliases'] if inst['apache']['aliases']
    aliases = aliases.flatten.uniq.compact

    deploy_to =  "#{node['chiliproject']['root_dir']}/#{inst['id']}"

    webapp hostname do
      docroot "#{deploy_to}/current/public"

      server_name hostname
      server_aliases aliases
      log_dir node['apache']['log_dir']

      passenger_paths ["/"]

      http_port inst['http_port'] || (base_uri(inst).scheme == "http" && base_uri(inst).port) || "80"
      https_port inst['https_port'] || (base_uri(inst).scheme == "https" && base_uri(inst).port) || "443"

      ssl (base_uri(inst).scheme == "https")
      ssl_certificate_file inst['ssl_certificate_file']
      ssl_key_file inst['ssl_key_file']
      ssl_ca_certificate_file inst['ssl_ca_certificate_file']

      template node['chiliproject']['apache']['template']
      cookbook node['chiliproject']['apache']['cookbook']
    end

    instances_to_restart << deploy_to
  else
    ##########################################################################
    # We have a vhost with multiple instances on subpaths

    apache_docroot = node['chiliproject']['apache']['docroot'] + "/#{hostname}"
    directory apache_docroot do
      owner "root"
      group node['apache']['group']
      mode "755"
      recursive true
    end

    webapp_params = {}
    paths.each_pair do |path, inst|
      aliases += inst['apache']['aliases'] if inst['apache']['aliases']
      deploy_to = "#{node['chiliproject']['root_dir']}/#{inst['id']}"

      link "apache_docroot/#{base_uri(inst).path}" do
        to "#{deploy_to}/current/public"
        owner "chili_#{inst['id'].downcase.gsub(/[^a-z]/, '_')}"
        group "chili_#{inst['id'].downcase.gsub(/[^a-z]/, '_')}"
      end

      http_port = inst['apache']['http_port'] || (base_uri(inst).scheme == "http" && base_uri(inst).port) || "80"
      if webapp_params[:http_port].nil? || webapp_params[:http_port] == http_port
        webapp_params[:http_port] = http_port
      else
        raise "Two or more ChiliProject sub path instances have different http ports defined"
      end

      https_port = inst['apache']['https_port'] || (base_uri(inst).scheme == "https" && base_uri(inst).port) || "443"
      if webapp_params[:https_port].nil? || webapp_params[:https_port] == https_port
        webapp_params[:https_port] = https_port
      else
        raise "Two or more ChiliProject sub path instances have different https ports defined"
      end

      %w(ssl_certificate_file ssl_key_file ssl_ca_certificate_file).each do |key|
        if webapp_params[key.to_sym].nil? || webapp_params[keys.to_sym] == inst['apache'][key]
          webapp_params[keys.to_sym] = inst['apache'][key]
        else
          raise "Two or more ChiliProject sub path instances have different #{key} keys"
        end
      end

      instances_to_restart << deploy_to
    end

    webapp hostname do
      docroot apache_docroot
      server_name hostname
      server_aliases aliases.flatten.uniq.compact
      log_dir node['apache']['log_dir']

      passenger_paths paths.keys

      webapp_params.each_pair do |k, v|
        send(k, v)
      end

      template node['chiliproject']['apache']['template']
      cookbook node['chiliproject']['apache']['cookbook']
    end
  end
end

##########################################################################
# 3. restart instances if necessary

instances_to_restart.uniq.each do |deploy_to|
  if File.exists?("#{deploy_to}/current")
    d = resource(:deploy_revision => "ChiliProject #{inst['id']}")
    d.restart_command do
      file "#{d.deploy_to}/current/tmp/restart.txt" do
        action :touch
      end
    end
  end
end
