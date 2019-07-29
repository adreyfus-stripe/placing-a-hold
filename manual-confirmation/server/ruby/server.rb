require 'stripe'
require 'sinatra'
require 'dotenv'

Dotenv.load(File.dirname(__FILE__) + '/../../.env')
Stripe.api_key = ENV['STRIPE_SECRET_KEY']

set :static, true
set :public_folder, File.join(File.dirname(__FILE__), '../../client/')
set :port, 4242

get '/' do
  # Display checkout page
  content_type 'text/html'
  send_file File.join(settings.public_folder, 'index.html')
end

def calculate_order_amount(_items)
  # Replace this constant with a calculation of the order's amount
  # Calculate the order total on the server to prevent
  # people from directly manipulating the amount on the client
  1400
end

get '/stripe-key' do
  content_type 'application/json'
  # Send public key to client
  {
    publicKey: ENV['STRIPE_PUBLIC_KEY']
  }.to_json
end

post '/pay' do
  data = JSON.parse(request.body.read)
  order_amount = calculate_order_amount(data['items'])

  begin
    if !data['paymentIntentId']
      # Create a new PaymentIntent for the order
      intent = Stripe::PaymentIntent.create(
        amount: order_amount,
        currency: data['currency'],
        payment_method: data['paymentMethodId'],
        confirmation_method: 'manual',
        capture_method: 'manual',
        confirm: true
      )
    else
      # Confirm the PaymentIntent to collect the money
      intent = Stripe::PaymentIntent.confirm(data['paymentIntentId'])
    end

    if intent['status'] == 'requires_capture'
      puts '❗ Charging the card for: ' + intent['amount_capturable'].to_s
      # Because capture_method was set to manual we need to manually capture in order to move the funds
      # You have 7 days to capture a confirmed PaymentIntent
      # To cancel a payment before capturing use .cancel() (https://stripe.com/docs/api/payment_intents/cancel)
      intent = Stripe::PaymentIntent.capture(intent['id'])
    end

    generate_response(intent)
  rescue Stripe::StripeError => e
    content_type 'application/json'
    {
      error: e.message
    }.to_json
  end
end

def generate_response(intent)
  content_type 'application/json'
  case intent['status']
  when 'requires_action', 'requires_source_action'
    # Card requires authentication
    {
      requiresAction: true,
      paymentIntentId: intent['id'],
      clientSecret: intent['client_secret']
    }.to_json
  when 'requires_payment_method', 'requires_source'
    # Card was not properly authenticated, new payment method required
    {
      error: 'Your card was denied, please provide a new payment method'
    }.to_json
  when 'succeeded'
    # Payment is complete, authentication not required
    # To cancel the payment after capture you will need to issue a Refund (https://stripe.com/docs/api/refunds)
    puts '💰 Payment received!'
    {
      clientSecret: intent['client_secret']
    }.to_json
  end
end