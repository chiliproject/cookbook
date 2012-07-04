maintainer       "ChiliProject Community"
maintainer_email "info@chiliproject.org"
license          "MIT"
description      "Installs/Configures ChiliProject"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.0.1"

recipe "chiliproject", "Installs ChiliProject"
recipe "chiliproject::database", "Setup required databases and users for ChiliProject"

%w{debian ubuntu}.each do |os|
  supports os
end

depends "git"
depends "logrotate"
depends "imagemagick"
depends "apache2"
depends "passenger_apache2"

depends "database"
depends "postgresql"
depends "mysql"
depends "sqlite"
