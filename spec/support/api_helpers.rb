module ApiHelpers
  def api_headers(token)
    { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" }
  end

  def json = JSON.parse(response.body)
end
