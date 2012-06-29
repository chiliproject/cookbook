define :chiliproject_deploy_key, :name => "default", :instance => {} do
  inst = params[:instance]

  deploy_to = "#{node['chiliproject']['root_dir']}/#{inst['id']}"
  chili_user = "chili_#{inst['id'].downcase.gsub(/[^a-z]/, '_')}"
  chili_group = chili_user

  if inst.has_key?("deploy_key")
    ruby_block "write_key" do
      block do
        f = ::File.open("#{deploy_to}/id_deploy", "w")
        f.print(inst["deploy_key"])
        f.close
      end
      not_if do ::File.exists?("#{deploy_to}/id_deploy"); end
    end

    file "#{deploy_to}/id_deploy" do
      owner chili_user
      group chili_group
      mode '0400'
    end

    template "#{deploy_to}/deploy-ssh-wrapper" do
      source "deploy-ssh-wrapper.erb"
      owner chili_user
      group chili_group
      mode "0755"
      variables :deploy_to => deploy_to
    end
  end

  if inst.has_key?('netrc')
    template "#{deploy_to}/.netrc" do
      source "netrc.erb"
      variables ({
        :hostname => inst['netrc']['hostname'],
        :username => inst['netrc']['username'],
        :password => inst['netrc']['password']
      })
      owner chili_user
      group chili_group
      mode '0400'
    end
  end
end
