self.class.send(:include, ChiliProject::Helpers)

data_bag("chiliproject").each do |name|
  inst = chiliproject_instance(name)

  # Check if the database should be created
  # This could be disabled on the application server node and be done directly
  # on the database box if desired to prevent the superuser credentials to be
  # passed over the wire and to be present on this box
  unless inst['database']['create_if_missing']
    log("Not attempting to create database #{inst['database']['database']}"){level :info}
    next
  end

  db_connection = db_admin_connection_info(inst)

  case inst['database']['adapter']
  when "mysql2"
    include_recipe "mysql::ruby"

    # Create the user
    mysql_database_user inst['database']['username'] do
      password inst['database']['password']
      action :create
      connection db_connection
    end

    # Create the database
    mysql_database inst['database']['database'] do
      encoding inst['database']['encoding'].downcase
      collation inst['database']['collation']
      action :create
      connection db_connection
    end
    mysql_database "set encoding for #{inst['database']['database']}" do
      sql "ALTER DATABASE #{inst['database']['database']} CHARACTER SET #{inst['database']['encoding'].downcase}"
      action :query
      connection db_connection
    end

    # Grant the user full rights on the database
    mysql_database_user inst['database']['username'] do
      action :grant
      database_name inst['database']['database']
      host '%'
      privileges [:ALL]
      connection db_connection
    end

    mysql_database "flush privileges" do
      sql "FLUSH PRIVILEGES"
      action :query
      connection db_connection
    end
  when "postgresql"
    include_recipe "postgresql::ruby"

    # Create the user
    postgresql_database_user inst['database']['username'] do
      password inst['database']['password']
      action :create
      connection db_connection
    end

    # Create the database, set the user as the owner
    postgresql_database inst['database']['database'] do
      action :create
      owner inst['database']['username']
      encoding inst['database']['encoding']
      collation inst['database']['collation']
      connection_limit inst['database']['connection_limit']
      template "template0"
      connection db_connection
    end

    # Grant the user full rights on the database
    postgresql_database_user inst['database']['username'] do
      action :grant
      database_name inst['database']['database']
      privileges [:ALL]
      connection db_connection
    end
  when "sqlite3"
    include_recipe "chiliproject::sqlite-ruby"

    directory File.dirname(inst['database']['database']) do
      recursive true
    end

    file inst['database']['database'] do
      owner inst['user']
      group inst['group']
      mode "0600"
      backup false
    end
  else
    raise "Unknown database adapter #{@instance['database']['adapter']} configured for instance #{instance['id']}"
  end
end
