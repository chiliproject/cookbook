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
  aliases = [node['fqdn']]
  aliases += paths.values.collect{|inst| inst['id'] + (node['domain'] ? ".#{node['domain']}" : "") }
  aliases << node['cloud']['public_hostname'] if node.has_key?("cloud")

  if paths.keys == ["/"]
    ##########################################################################
    # We have a vhost with a single instance on the root path

    inst = paths["/"]
    inst_base_uri = base_uri(inst)

    aliases += inst['apache']['aliases'] if inst['apache'] && inst['apache']['aliases']
    aliases = aliases.flatten.uniq.compact

    deploy_to =  "#{node['chiliproject']['root_dir']}/#{inst['id']}"

    web_app hostname do
      docroot "#{deploy_to}/current/public"

      server_name hostname
      server_aliases aliases
      log_dir node['apache']['log_dir']

      passenger_paths ["/"]

      http_port inst['http_port'] || (inst_base_uri.scheme == "http" && inst_base_uri.port) || "80"
      https_port inst['https_port'] || (inst_base_uri.scheme == "https" && inst_base_uri.port) || "443"

      ssl (inst_base_uri.scheme == "https")
      ssl_certificate_file inst['ssl_certificate_file']
      ssl_key_file inst['ssl_key_file']
      ssl_ca_certificate_file inst['ssl_ca_certificate_file']

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
      mode "755"
      recursive true
    end

    web_app_params = {}
    paths.each_pair do |path, inst|
      aliases += [inst['apache']['aliases']] if inst['apache'] && inst['apache']['aliases']
      deploy_to = "#{node['chiliproject']['root_dir']}/#{inst['id']}"

      link "apache_docroot/#{base_uri(inst).path}" do
        to "#{deploy_to}/current/public"
        owner "chili_#{inst['id'].downcase.gsub(/[^a-z]/, '_')}"
        group "chili_#{inst['id'].downcase.gsub(/[^a-z]/, '_')}"
      end

      http_port = inst['apache']['http_port'] || (base_uri(inst).scheme == "http" && base_uri(inst).port) || "80"
      if web_app_params[:http_port].nil? || web_app_params[:http_port] == http_port
        web_app_params[:http_port] = http_port
      else
        raise "Two or more ChiliProject sub path instances have different http ports defined"
      end

      https_port = inst['apache']['https_port'] || (base_uri(inst).scheme == "https" && base_uri(inst).port) || "443"
      if web_app_params[:https_port].nil? || web_app_params[:https_port] == https_port
        web_app_params[:https_port] = https_port
      else
        raise "Two or more ChiliProject sub path instances have different https ports defined"
      end

      %w(ssl_certificate_file ssl_key_file ssl_ca_certificate_file).each do |key|
        if web_app_params[key.to_sym].nil? || web_app_params[keys.to_sym] == inst['apache'][key]
          web_app_params[keys.to_sym] = inst['apache'][key]
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

      passenger_paths paths.keys

      web_app_params.each_pair do |k, v|
        send(k, v)
      end

      template node['chiliproject']['apache']['template']
      cookbook node['chiliproject']['apache']['cookbook']
    end
  end
end

##########################################################################
# 4. Disable the default Apache vhost

if vhosts.any?
  apache_site "000-default" do
    enable params[:disable]
  end
end


##########################################################################
# 4. restart instances if necessary

instances_to_restart.uniq.each do |inst|
  deploy_to = "#{node['chiliproject']['root_dir']}/#{inst['id']}"

  if File.exists?("#{deploy_to}/current")
    d = resources(:deploy_revision => "ChiliProject #{inst['id']}")
    d.restart_command do
      file "#{d.deploy_to}/current/tmp/restart.txt" do
        action :touch
      end
    end
  end
end
