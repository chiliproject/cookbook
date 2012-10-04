require 'uri'

module ChiliProject
  module Helpers
    def chiliproject_instance(name)
      node.run_state['chiliproject_instances'] ||= {}
      node.run_state['chiliproject_instances'][name.to_s] ||= begin
        inst = data_bag_item('chiliproject', name.to_s)

        # Set up sane defaults
        inst['user'] ||= "chili_#{inst['id'].downcase.gsub(/[^a-z]/, '_')}"
        inst['group'] ||= inst['user']
        inst['deploy_to'] ||= "#{node['chiliproject']['root_dir']}/#{inst['id']}"
        inst['log_dir'] ||= "#{node['chiliproject']['log_dir']}/#{inst['id']}"
        inst['shared_dir'] ||= "#{node['chiliproject']['shared_dir']}/#{inst['id']}"

        %w[repository revision repository_hosting].each do |k|
          inst[k] ||= node['chiliproject'][k]
        end
        %w[migrate force_deploy bundle_vendor logrotate].each do |k|
          inst[k] = node['chiliproject'][k] unless inst.has_key?(k)
        end

        %w[local_gems config_files].each do |k|
          inst[k] = Chef::Mixin::DeepMerge.merge(node['chiliproject'][k].to_hash, inst[k] || {})
        end

        inst['base_uri'] = inst['base_uri'] ? URI.parse(inst['base_uri']) : URI.parse("")
        inst['base_uri'].tap do |base_uri|
          base_uri.scheme ||= "http"
          base_uri.host ||= inst['id'].gsub(/_/, '.')
          base_uri.path = "/" if base_uri.path == ""
        end
        inst['database'] = chiliproject_database(inst)
        inst['rails_env'] ||= node.chef_environment =~ /_default/ ? 'production' : node.chef_environment.to_s
        inst['apache'] = node['chiliproject']['apache'].merge(inst['apache'] || {}) do |key, old_value, new_value|
          # The document root can only be set on the node
          %w[document_root].include?(key) ? old_value : new_value
        end

        inst['plugins'] ||= {}
        inst['settings'] ||= {}

        inst.to_hash
      end
    end

    def get_hosts(instance, prefix=[], role_key="role", hostname_key="hostname")
      prefix = [prefix].flatten
      instance_parent = prefix.inject(instance){|h, k| h.send(:[], k)} || {}
      node_parent = prefix.inject(node['chiliproject']){|h, k| h.send(:[], k)} || {}

      role = instance_parent.has_key?(role_key) ? instance_parent[role_key] : node_parent[role_key]
      if role
        search(:node, "role:#{role} AND chef_environment:#{node.chef_environment}")
      else
        hosts = instance_parent[hostname_key]
        hosts ||= node_parent[hostname_key]
        hosts = [hosts].flatten.compact

        hosts.collect do |host|
          node = Chef::Node.new
          node.name host
          node.hostname host
          node.ipaddress host
          node
        end
      end
    end

    def chiliproject_database(instance)
      db = node['chiliproject']['database'].to_hash

      hash = db.merge(instance['database'] || {}) do |key, old_value, new_value|
        new_value.nil? ? old_value : new_value
      end

      # these are the hash keys that are not intended to be included into the
      # generated database.yml
      internal_keys = %w[
        create_if_missing backup_before_migrate role superuser
        superuser_password hostname collation
      ]

      case hash['adapter']
      when /sqlite/i
        hash['adapter'] = "sqlite3"
        db_slug = "#{node['chiliproject']['root_dir']}/#{instance['id']}/shared/#{instance['rails_env']}.db"
        # sqlite is not external, so we don't have these additional keys
        internal_keys += %w[username password host port reconnect]
      when /mysql/i
        hash['adapter'] = "mysql2"
        db_slug = "chili_#{instance['id'].downcase.gsub(/[^a-z]/, '_')}"[0..15]
        hash['port'] ||= 3306
        hash['collation'] ||= "utf8_unicode_ci"
      when /postgres/i
        hash['adapter'] = "postgresql"
        db_slug = "chili_#{instance['id'].downcase.gsub(/[^a-z]/, '_')}"
        hash['port'] ||= 5432
        hash['collation'] ||= "en_US.utf8"
      else
        raise "Unknown database adapter #{hash['adapter']} specified for ChiliProject #{instance['id']}"
      end

      hash['database'] ||= db_slug
      unless hash['adapter'] == "sqlite3"
        hash['host'] = get_hosts(instance, 'database', 'role', 'hostname').first.ipaddress
        hash['username'] ||= db_slug

        if !hash['password'] || hash['password'].strip == ""
          raise "The ChiliProject instance #{instance['id']} needs a password!"
        end
      end

      database_yml = hash.reject do |k, v|
        internal_keys.include?(k.to_s)
      end
      if database_yml.delete('ssl')
        # TODO: setup SSL for database connectivity
      end
      hash['database_yml'] = database_yml

      hash
    end

    def db_admin_connection_info(instance)
      # Returns the DB connection info required to create users and databases
      # This data should not be used for normal operation.

      info = {
        :database => instance['database']['database']
      }

      unless instance['database']['adapter'] == "sqlite3"
        info[:host] = instance['database']['host']
        info[:port] = instance['database']['port']
        info[:username] = instance['database']['superuser']
        info[:password] = instance['database']['superuser_password']
      end

      case instance['database']['adapter']
      when "mysql2"
        info[:username] ||= "root"
        info[:password] ||= node['mysql']['server_root_password']
      when "postgresql"
        info[:database] = "postgres"
      when "sqlite3"
        # do nothing special here
      end

      info
    end
  end
end
