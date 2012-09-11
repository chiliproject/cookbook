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
  end
end
