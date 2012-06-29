require 'uri'

module ChiliProject
  module Helpers
    def base_uri(instance)
      return instance['base_uri'] if instance['base_uri'].is_a?(URI)

      base_uri = instance['base_uri'] ? URI(instance['base_uri']) : URI("")
      base_uri.host ||= instance['id'].gsub(/_/, '.')
      base_uri.path ||= "/"

      instance['base_uri'] = base_uri
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

    def db_hash(instance)
      db = node['chiliproject']['database'].to_hash

      hash = db.merge(instance['database']) do |key, old_value, new_value|
        new_value.nil? ? old_value : new_value
      end

      case hash['adapter']
      when /sqlite/i
        hash[:adapter] = "sqlite3"
        db_slug = "#{node['chiliproject']['root_dir']}/#{instance['id']}/shared/#{node.run_state[:rails_env]}.db"
      when /mysql/i
        hash[:adapter] = "mysql2"
        db_slug = "chili_#{instance['id'].downcase.gsub(/[^a-z]/, '_')}"[0..15]
        db_port = 3306
      when /postgres/i
        hash[:adapter] = "postgresql"
        db_slug = "chili_#{instance['id'].downcase.gsub(/[^a-z]/, '_')}"
        db_port = 5432
      else
        raise "Unknown database adapter #{hash['adapter']} specified for ChiliProject #{instance['id']}"
      end

      hash['database'] ||= db_slug
      unless hash['adapter'] == "sqlite3"
        hash['host'] = get_hosts(instance, 'database', 'role', 'hostname').first.ipaddress
        hash['username'] ||= db_slug
        hash['port'] ||= db_port

        if !hash['password'] || hash['password'].strip == ""
          raise "The ChiliProject instance #{instance['id']} needs a password!"
        end
      end

      hash
    end
  end
end
