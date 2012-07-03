self.class.send(:include, ChiliProject::Helpers)

instances = Chef::DataBag.load("chiliproject").values
instances.each do |inst|
  inst = chiliproject_instance(inst)

  case inst['database']['adapter']
  when "mysql2"
    include_recipe "mysql::client"
    chef_gem "mysql" # make the mysql gem available imediately
  when "postgresql"
    include_recipe "postgresql::client"
  when "sqlite3"
    include_recipe "sqlite"
    package "libsqlite3-dev" # probably specific to Debian/Ubuntu
  else
    # nothing to do for unknown database type
    next
  end

  # Check if the database should be created
  # This could be disabled on the application server node and be done directly
  # on the database box if desired to prevent the superuser credentials to be
  # passed over the wire and to be present on this box
  unless inst['database']['create_if_missing']
    log("Not attempting to create database #{inst['database']['database']}"){level :info}
    next
  end

  db_connection_info = {
    :host => inst['database']['host'],
    :username => inst['database']['superuser'],
    :password => inst['database']['superuser_password']
  }

  case inst['database']['adapter']
  when "mysql2"
    mysql_connection_info = db_connection_info.dup
    mysql_connection_info[:username] ||= "root"
    mysql_connection_info[:password] ||= node['mysql']['server_root_password']

    # Create the user
    mysql_database_user inst['database']['username'] do
      password inst['database']['password']
      action :create
      connection mysql_connection_info
    end

    # Create the database
    mysql_database inst['database']['database'] do
      encoding inst['database']['encoding'].downcase
      collation inst['database']['collation']
      action :create
      connection mysql_connection_info
    end
    mysql_database "set encoding for #{inst['database']['database']}" do
      sql "ALTER DATABASE #{inst['database']['database']} CHARACTER SET #{inst['database']['encoding'].downcase}"
      action :query
      connection mysql_connection_info
    end

    # Grant the user full rights on the database
    mysql_database_user inst['database']['username'] do
      action :grant
      database_name inst['database']['database']
      host '%'
      privileges [:ALL]
      connection mysql_connection_info
    end

    mysql_database "flush privileges" do
      sql "FLUSH PRIVILEGES"
      action :query
      connection mysql_connection_info
    end
  when "postgresql"
    pg_connection_info = db_connection_info.merge({
      :database => "postgres"
    })

    # Create the user
    postgresql_database_user inst['database']['username'] do
      password inst['database']['password']
      action :create
      connection pg_connection_info
    end

    # Create the database, set the user as the owner
    postgresql_database inst['database']['database'] do
      action :create
      owner inst['database']['username']
      encoding inst['database']['encoding']
      collation inst['database']['collation']
      connection_limit inst['database']['connection_limit']
      template "template0"
      connection pg_connection_info
    end

    # Grant the user full rights on the database
    postgresql_database_user inst['database']['username'] do
      action :grant
      database_name inst['database']['database']
      privileges [:ALL]
      connection pg_connection_info
    end
  when "sqlite3"
    directory File.dirname(inst['database']['database']) do
      recursive true
    end

    file inst['database']['database'] do
      owner inst['user']
      group inst['group']
      mode "0600"
      backup false
    end
  end
end
