# This recipe is only used until the opscode sqlite cookbook gains capabilities
# similar to the mysql and postgresql cookbooks, i.e. a client and ruby recipe.

execute "apt-get update" do
  ignore_failure true
  action :nothing
end.run_action(:run) if node['platform_family'] == "debian"

node.set['build_essential']['compiletime'] = true
include_recipe "build-essential"
include_recipe "sqlite"

header_package = value_for_platform_family(
  ["redhat", "suse", "fedora" ] => {
    "default" => "sqlite-devel"
  },
  ["debian"] => {
    "default" => "libsqlite3-dev"
  },
  'default' => "libsqlite3-dev"
)

package header_package do
  action :nothing
end.run_action(:install)

chef_gem "sqlite3"
