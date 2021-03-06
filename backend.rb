require 'base64'
require 'httparty'
require 'logger'
require 'sinatra/base'

if ENV['RACK_ENV'] == 'development'
  require 'sinatra/reloader'
  require 'pry'
end

class Backend < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  request_log = Logger.new STDOUT
  request_log.info "Incoming/outgoing API requests will be logged to the console."

  # Note: Storing your actual Klarna credentials this way is a bad idea
  API_KEY = ENV['API_KEY'] || 'test_d8324b98-97ce-4974-88de-eaab2fdf4f14'
  API_SECRET = ENV['API_SECRET'] || 'test_846853f798502446dbaf11ee8365fef2e533ddde1f5d6a6caa961398a776c08c'

  # This represents the system's "inventory", mapping reference strings to movie
  # tickets.
  CATALOG = {
    'TCKT0001' => {
      name:     'Movie ticket - The Girl with the Dragon Tattoo',
      cost:     9900,
      currency: 'SEK',
      tax_cost: 900
    }
  }

  # Allow cross-domain calls
  before do
    response.headers['Access-Control-Allow-Origin'] = '*'
  end

  options '/pay' do
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
    response.headers['Access-Control-Allow-Methods'] = 'POST, OPTIONS'
    status 200
  end

  # Handle POST requests to '/pay'
  post '/pay' do
    # Make key-value pairs from the JSON body available in the 'params' hash
    params.merge!(JSON.parse(request.body.read))

    logging_options = {
      logger: request_log,
      log_level: :debug,
      log_format: :curl
    }

    # Build and send a request to authorize the purchase
    item = CATALOG[params[:reference]]

    authorize_request = {
      basic_auth: { username: API_KEY, password: API_SECRET },
      headers: { 'Content-Type' => 'application/json' },
      body: {
        reference:        params[:reference],
        name:             item[:name],
        order_amount:     item[:cost],
        order_tax_amount: item[:tax_cost],
        currency:         item[:currency],
        capture:          false,
        origin_proof:     params[:origin_proof]
      }.to_json
    }

    authorize_url = "https://inapp.playground.klarna.com/api/v1/users/#{params[:user_token]}/orders"
    authorize_response = HTTParty.post(authorize_url, authorize_request.merge(logging_options))

    if authorize_response && authorize_response.code == 201
      # The purchase was authorized (and has essentially been created as a
      # resource available at the location specified in the authorization
      # requests's response). Capture it.
      capture_request = {
        basic_auth: { username: API_KEY, password: API_SECRET },
      }

      capture_url = authorize_response + "/capture"
      capture_response = HTTParty.post(capture_url, capture_request.merge(logging_options))
    else
      halt authorize_response.code, 'Failed to authorize purchase'
    end

    if capture_response && capture_response.code == 200
      # The purchase has been successfully captured, respond with 204
      status 204
    else
      halt capture_response.code, 'Failed to capture order'
    end
  end
end
