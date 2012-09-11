module ChiliProject
  module ApacheHelpers
    def common_url(ssl=@params[:ssl])
      if ssl
        port = ":#{@params[:https_port]}" unless @params[:https_port] == 443
        "https://#{@application_name}#{port}"
      else
        port = ":#{@params[:http_port]}" unless @params[:http_port] == 80
        "http://#{@application_name}#{port}"
      end
    end

    def load_chiliproject_pm
      return if @chiliproject_pm_loaded

      @chiliproject_pm_loaded = true
      if @params[:passenger_paths].values.any?{ |inst| inst['repository_hosting'].any? }
        "PerlLoadModule Apache::ChiliProject"
      end
    end
  end
end
