extend ChiliProject::Helpers

include_recipe "apache2::mod_perl"

instance = node['chiliproject']['chiliproject_pm']['instance']
instance ||= data_bag(node["chiliproject"]["databag"]).first
inst = chiliproject_instance(instance)

perl_lib_dir = node['chiliproject']['chiliproject_pm']['perl_lib_dir']
directory "#{perl_lib_dir}/Apache" do
  recursive true
end

link "#{perl_lib_dir}/Apache/ChiliProject.pm" do
  to "#{inst['deploy_to']}/current/extra/svn/ChiliProject.pm"
  notifies :reload, "service[apache2]"
end

