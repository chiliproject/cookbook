self.class.send(:include, ChiliProject::Helpers)

instances = Chef::DataBag.load("chiliproject").values
instances.each do |inst|
  db = db_hash(inst)

  case db['adapter']
  when "mysql2"
    include_recipe "mysql::client"
    chef_gem "mysql" # make the mysql gem available imediately
  when "postgresql"
    include_recipe "postgresql::client"
  else
    include_recipe "sqlite"
    package "libsqlite3-dev" # probably specific to Debian/Ubuntu
    # nothing more to do
    next
  else
    # nothing to do for unknown database type
    next
  end

  # Check if the database should be created
  # This could be disabled on the application server node and be done directly
  # on the database box if desired to prevent the superuser credentials to be
  # passed over the wire and to be present on this box
  unless db['create_if_missing']
    log("Not attempting to create database #{db['database']}"){level :info}
    next
  end

  db_connection_info = {
    :host => db['host'],
    :username => db['superuser'],
    :password => db['superuser_password']
  }

  case db['adapter']
  when "mysql2"
    mysql_connection_info = {
      :password => node['mysql']['server_root_password']
    }.merge(db_connection_info)

    # Create the user
    mysql_database_user db['username'] do
      password db['password']
      action :create
      connection mysql_connection_info
    end

    # Create the database
    mysql_database db['database'] do
      action :create
      connection db_connection_info
    end
    mysql_database "set encoding for #{db['database']}" do
      sql "ALTER DATABASE #{db['database']} CHARACTER SET #{db['encoding'].downcase}"
      action :query
      connection mysql_connection_info
    end

    # Grant the user full rights on the database
    mysql_database_user db['username'] do
      action :grant
      database_name db['database']
      host '%'
      privileges [:ALL]
      connection mysql_connection_info
    end

    mysql_database "flush privileges" do
      sql "FLUSH PRIVILEGES"
      action :query
      connection db_connection_info
    end
  when "postgresql"
    pg_connection_info = db_connection_info.merge({
      :database => "postgres"
    })

    # Create the user
    postgresql_database_user db['username'] do
      password db['password']
      action :create
      connection pg_connection_info
    end

    # Create the database, set the user as the owner
    postgresql_database db['database'] do
      action :create
      owner db['username']
      encoding db['encoding'].upcase
      connection_limit db['connection_limit']
      template "template0"
      connection pg_connection_info
    end

    # Grant the user full rights on the database
    postgresql_database_user db['username'] do
      action :grant
      database_name db['database']
      privileges [:ALL]
      connection pg_connection_info
    end
  end
end
